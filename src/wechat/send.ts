import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { WeChatApi } from './api.js';
import { MessageItemType, MessageType, MessageState, TypingStatus, type MessageItem, type OutboundMessage } from './types.js';
import { uploadFile } from './upload.js';
import { logger } from '../logger.js';
import {
  simulateReadReceiptDelay,
  simulateTypingDelay,
  simulateThinkTime,
  maybeIdlePause,
} from './antidetect.js';

const TYPING_KEEPALIVE_MS = 5_000;

export function createSender(api: WeChatApi, botAccountId: string) {
  let clientCounter = 0;
  const typingTicketCache = new Map<string, { ticket: string; fetchedAt: number }>();
  const TICKET_TTL = 24 * 60 * 60 * 1000;

  function generateClientId(): string {
    // Use a jittered timestamp to avoid sequential message IDs
    const jittered = Date.now() + Math.floor(Math.random() * 1000);
    return `wcc-${jittered}-${++clientCounter}`;
  }

  async function getTypingTicket(userId: string, contextToken?: string): Promise<string> {
    const cached = typingTicketCache.get(userId);
    if (cached && Date.now() - cached.fetchedAt < TICKET_TTL) {
      return cached.ticket;
    }
    try {
      const resp = await api.getConfig(userId, contextToken);
      if (resp.ret === 0 && resp.typing_ticket) {
        typingTicketCache.set(userId, { ticket: resp.typing_ticket, fetchedAt: Date.now() });
        return resp.typing_ticket;
      }
      logger.warn('getConfig returned no typing_ticket', { ret: resp.ret });
    } catch (err) {
      logger.warn('getConfig failed', { err: err instanceof Error ? err.message : String(err) });
    }
    return '';
  }

  /**
   * Start typing indicator with keepalive. Returns a stop function.
   * Fire-and-forget: errors are logged but not thrown.
   */
  function startTyping(toUserId: string, contextToken: string): () => void {
    let cancelled = false;

    (async () => {
      const ticket = await getTypingTicket(toUserId, contextToken);
      if (!ticket || cancelled) return;

      try {
        await api.sendTyping({
          ilink_user_id: toUserId,
          typing_ticket: ticket,
          status: TypingStatus.TYPING,
        });
      } catch (err) {
        logger.debug('sendTyping start failed', { err: err instanceof Error ? err.message : String(err) });
        return;
      }

      // Keepalive loop with jittered timing
      while (!cancelled) {
        // Add ±1s jitter to keepalive to avoid fixed-interval pattern
        const jitter = Math.floor((Math.random() - 0.5) * 2000);
        await new Promise(r => setTimeout(r, TYPING_KEEPALIVE_MS + jitter));
        if (cancelled) break;
        try {
          await api.sendTyping({
            ilink_user_id: toUserId,
            typing_ticket: ticket,
            status: TypingStatus.TYPING,
          });
        } catch {
          break;
        }
      }

      // Send CANCEL to tell WeChat we're done typing
      if (!ticket) return;
      try {
        await api.sendTyping({
          ilink_user_id: toUserId,
          typing_ticket: ticket,
          status: TypingStatus.CANCEL,
        });
      } catch {
        // ignore
      }
    })();

    return () => {
      cancelled = true;
    };
  }

  async function sendText(toUserId: string, contextToken: string, text: string): Promise<void> {
    // Simulate human reading delay before responding
    await simulateReadReceiptDelay();

    const clientId = generateClientId();

    const items: MessageItem[] = [
      {
        type: MessageItemType.TEXT,
        text_item: { text },
      },
    ];

    const msg: OutboundMessage = {
      from_user_id: botAccountId,
      to_user_id: toUserId,
      client_id: clientId,
      message_type: MessageType.BOT,
      message_state: MessageState.FINISH,
      context_token: contextToken,
      item_list: items,
    };

    logger.info('Sending text message', { toUserId, clientId, textLength: text.length });

    // Add a small random delay before sending to simulate human typing
    // This is applied per-chunk so multi-chunk messages also look natural
    const typingDelay = simulateTypingDelay(text);
    await new Promise(r => setTimeout(r, Math.min(typingDelay, 3000))); // cap at 3s

    await api.sendMessage({ msg });
    logger.info('Text message sent', { toUserId, clientId });

    // Occasionally insert an idle pause after sending (simulates user checking response)
    // Fire-and-forget — don't block the caller
    maybeIdlePause().catch(() => {});
  }

  async function sendFile(toUserId: string, contextToken: string, filePath: string): Promise<void> {
    // Resolve tilde on any platform
    const homeDir = process.env.USERPROFILE || process.env.HOME || '';
    const resolved = resolve(filePath.replace(/^~/, homeDir));
    if (!existsSync(resolved)) {
      await sendText(toUserId, contextToken, `文件不存在: ${resolved}`);
      return;
    }

    try {
      const media = await uploadFile(api, toUserId, resolved);
      const clientId = generateClientId();

      // Simulate a short "preparing file" delay before sending
      await simulateThinkTime();

      // Convert aesKeyHex to base64: treat hex string as UTF-8, then base64 encode
      // (matches OpenClaw's format: Buffer.from(hexString).toString("base64"))
      const aesKeyBase64 = Buffer.from(media.aesKeyHex).toString('base64');

      let item: MessageItem;
      if (media.mediaType === 'image') {
        item = {
          type: MessageItemType.IMAGE,
          image_item: {
            media: {
              encrypt_query_param: media.encryptQueryParam,
              aes_key: aesKeyBase64,
              encrypt_type: 1,
            },
            mid_size: media.fileSize,
          },
        };
      } else {
        item = {
          type: MessageItemType.FILE,
          file_item: {
            media: {
              encrypt_query_param: media.encryptQueryParam,
              aes_key: aesKeyBase64,
              encrypt_type: 1,
            },
            file_name: media.fileName,
            len: String(media.rawSize),
          },
        };
      }

      const msg: OutboundMessage = {
        from_user_id: botAccountId,
        to_user_id: toUserId,
        client_id: clientId,
        message_type: MessageType.BOT,
        message_state: MessageState.FINISH,
        context_token: contextToken,
        item_list: [item],
      };

      logger.info('Sending file message', { toUserId, clientId, fileName: media.fileName, mediaType: media.mediaType });
      await api.sendMessage({ msg });
      logger.info('File message sent', { toUserId, clientId, fileName: media.fileName });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('Failed to send file', { filePath: resolved, error: msg });
      if (!msg.includes('rate-limited')) {
        await sendText(toUserId, contextToken, `发送文件失败: ${msg}`);
      }
      throw err;
    }
  }

  return { sendText, startTyping, sendFile };
}
