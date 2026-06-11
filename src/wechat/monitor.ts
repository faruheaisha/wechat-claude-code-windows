import { WeChatApi } from './api.js';
import { loadSyncBuf, saveSyncBuf } from './sync-buf.js';
import { logger } from '../logger.js';
import type { WeixinMessage } from './types.js';
import {
  jitterInterval,
  getAdaptivePollInterval,
  getRandomUserAgent,
  getCurrentActivityLevel,
} from './antidetect.js';

const SESSION_EXPIRED_ERRCODE = -14;
const SESSION_EXPIRED_PAUSE_MS = 60 * 60 * 1000; // 1 hour
const SESSION_EXPIRED_JITTER_MS = 10 * 60 * 1000; // ±10 min jitter
const BACKOFF_THRESHOLD = 3;
const BACKOFF_LONG_MS = 30_000;
const BACKOFF_SHORT_MS = 3_000;
const BASE_POLL_INTERVAL_MS = 3_000;
const HEALTH_CHECK_INTERVAL_MS = 5 * 60 * 1000; // every 5 min
const MAX_CONSECUTIVE_FAILURES = 20; // max before entering error state
const RECOVERY_CHECK_INTERVAL_MS = 60_000; // retry health check every 60s when recovering
const MSG_DEDUP_CAPACITY = 2000;

export interface MonitorCallbacks {
  onMessage: (msg: WeixinMessage) => Promise<void>;
  onSessionExpired: () => void;
}

export function createMonitor(api: WeChatApi, callbacks: MonitorCallbacks) {
  const controller = new AbortController();
  let stopped = false;
  const recentMsgIds = new Set<number>();
  let lastHealthCheck = Date.now();
  let healthStatus: 'ok' | 'degraded' | 'failed' = 'ok';
  let consecutiveFailures = 0;

  /**
   * Health check: verify API connectivity by requesting bot config.
   * Uses a short timeout to avoid blocking the monitor loop.
   */
  async function checkHealth(): Promise<boolean> {
    try {
      const resp = await api.getConfig('health-check', undefined);
      const ok = resp.ret === 0 || (resp.ret !== undefined && resp.ret !== SESSION_EXPIRED_ERRCODE);
      if (ok) {
        healthStatus = 'ok';
        return true;
      }
      healthStatus = 'degraded';
      return false;
    } catch {
      healthStatus = 'failed';
      return false;
    }
  }

  /**
   * Calculate backoff time with jitter.
   * Exponentially increasing backoff until a cap, then randomized within the cap window.
   */
  function calculateBackoffMs(failures: number): number {
    if (failures <= 0) return 0;
    if (failures >= BACKOFF_THRESHOLD) {
      // Jitter within long backoff window
      return jitterInterval(BACKOFF_LONG_MS);
    }
    // Exponential backoff with jitter: 3s, 9s, then plateau
    const exponential = Math.min(BACKOFF_SHORT_MS * Math.pow(3, failures - 1), BACKOFF_LONG_MS);
    return jitterInterval(exponential);
  }

  async function run(): Promise<void> {
    while (!controller.signal.aborted) {
      try {
        // ---- Periodic health check ----
        if (Date.now() - lastHealthCheck > HEALTH_CHECK_INTERVAL_MS) {
          lastHealthCheck = Date.now();
          const healthy = await checkHealth();
          if (!healthy) {
            logger.warn('Health check: degraded API connectivity', { healthStatus });
          }
        }

        // If in recovery mode (after many failures), check health before polling
        if (healthStatus === 'failed' || healthStatus === 'degraded') {
          const recovered = await checkHealth();
          if (!recovered) {
            const wait = jitterInterval(RECOVERY_CHECK_INTERVAL_MS);
            logger.info('Monitor: connection degraded, waiting before retry', { waitMs: wait, healthStatus, consecutiveFailures });
            await sleep(wait, controller.signal);
            continue;
          }
          logger.info('Monitor: connection recovered', { healthStatus });
          healthStatus = 'ok';
          consecutiveFailures = 0;
        }

        // ---- Jittered delay before poll (anti-detection) ----
        const delay = getAdaptivePollInterval(BASE_POLL_INTERVAL_MS);
        await sleep(delay, controller.signal);

        // ---- Poll ----
        const buf = loadSyncBuf();
        logger.debug('Polling for messages', { hasBuf: buf.length > 0, activityLevel: getCurrentActivityLevel() });

        const resp = await api.getUpdates(buf || undefined);

        if (resp.ret === SESSION_EXPIRED_ERRCODE) {
          logger.warn('Session expired, pausing with jitter');
          callbacks.onSessionExpired();

          // Jitter the pause to avoid synchronous timing
          const jitteredPause = SESSION_EXPIRED_PAUSE_MS + randomInt(-SESSION_EXPIRED_JITTER_MS, SESSION_EXPIRED_JITTER_MS);
          await sleep(Math.max(jitteredPause, 5_000), controller.signal);
          consecutiveFailures = 0;
          continue;
        }

        if (resp.ret !== undefined && resp.ret !== 0) {
          logger.warn('getUpdates returned error', { ret: resp.ret, retmsg: resp.retmsg });
        }

        // Save the new sync buffer
        if (resp.get_updates_buf) {
          saveSyncBuf(resp.get_updates_buf);
        }

        // Process messages (with deduplication)
        const messages = resp.msgs ?? [];
        if (messages.length > 0) {
          logger.info('Received messages', { count: messages.length });
          for (const msg of messages) {
            // Skip already-processed messages
            if (msg.message_id && recentMsgIds.has(msg.message_id)) {
              continue;
            }
            if (msg.message_id) {
              recentMsgIds.add(msg.message_id);
              if (recentMsgIds.size > MSG_DEDUP_CAPACITY) {
                // Evict oldest half (Set iterates in insertion order)
                const iter = recentMsgIds.values();
                const toDelete: number[] = [];
                for (let i = 0; i < MSG_DEDUP_CAPACITY / 2; i++) {
                  const { value } = iter.next();
                  if (value !== undefined) toDelete.push(value);
                }
                for (const id of toDelete) recentMsgIds.delete(id);
              }
            }
            // Fire-and-forget: don't block the polling loop on message processing
            callbacks.onMessage(msg).catch((err) => {
              const msg2 = err instanceof Error ? err.message : String(err);
              logger.error('Error processing message', { error: msg2, messageId: msg.message_id });
            });
          }
        }

        consecutiveFailures = 0;
        if (healthStatus !== 'ok') healthStatus = 'ok';
      } catch (err) {
        if (controller.signal.aborted) {
          break;
        }

        consecutiveFailures++;
        const errorMsg = err instanceof Error ? err.message : String(err);
        logger.error('Monitor error', { error: errorMsg, consecutiveFailures });

        if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
          logger.error('Too many consecutive failures, entering health check recovery mode', { consecutiveFailures });
          healthStatus = 'failed';
          consecutiveFailures = 0;
        }

        const backoff = calculateBackoffMs(consecutiveFailures);
        logger.info(`Monitor: backing off ${backoff}ms`, { consecutiveFailures });
        await sleep(backoff, controller.signal);
      }
    }

    stopped = true;
    logger.info('Monitor stopped');
  }

  function stop(): void {
    if (!controller.signal.aborted) {
      logger.info('Stopping monitor...');
      controller.abort();
    }
  }

  return { run, stop };
}

function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise<void>((resolve) => {
    if (signal?.aborted) {
      resolve();
      return;
    }

    const timer = setTimeout(resolve, ms);
    signal?.addEventListener('abort', () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
  });
}
