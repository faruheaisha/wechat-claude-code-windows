/**
 * Anti-detection module: human-like behavior simulation.
 *
 * WeChat's anti-bot systems look for:
 *  - Fixed-interval polling (bots poll at exact intervals)
 *  - Instant reply speed (humans take time to "type" and "think")
 *  - Predictable timing patterns (bots have near-zero variance)
 *  - 24/7 activity with no idle periods
 *  - Exact same request patterns every time
 *
 * This module introduces controlled randomness and human-like timing
 * to all operations, making the bot behaviour harder to fingerprint.
 */

import { logger } from '../logger.js';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

interface AntiDetectConfig {
  /** Minimum "think" time before replying (ms) — simulates human reading. */
  minThinkTimeMs: number;
  /** Maximum "think" time before replying (ms). */
  maxThinkTimeMs: number;
  /** "Typing" speed: characters per second range (human: ~3-8 cps). */
  typingSpeedCps: { min: number; max: number };
  /** Probability of a random idle pause (0 = never, 1 = every message). */
  idlePauseProbability: number;
  /** Duration of idle pause when triggered (ms range). */
  idlePauseMs: { min: number; max: number };
  /** Add jitter to polling intervals (± fraction of the base interval). */
  pollJitterFraction: number;
  /** Random headers to rotate per-request (browser-like fingerprint). */
  userAgents: string[];
  /** Probability of simulating a "read receipt" delay. */
  readReceiptDelayProbability: number;
  /** Read receipt delay range (ms). */
  readReceiptDelayMs: { min: number; max: number };
}

const DEFAULT_CONFIG: AntiDetectConfig = {
  minThinkTimeMs: 800,
  maxThinkTimeMs: 3000,
  typingSpeedCps: { min: 3, max: 8 },
  idlePauseProbability: 0.15,
  idlePauseMs: { min: 5_000, max: 30_000 },
  pollJitterFraction: 0.25,
  userAgents: [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0',
  ],
  readReceiptDelayProbability: 0.4,
  readReceiptDelayMs: { min: 500, max: 2000 },
};

// Singleton config (can be updated at runtime)
let config: AntiDetectConfig = { ...DEFAULT_CONFIG };

// ---------------------------------------------------------------------------
// Random helpers
// ---------------------------------------------------------------------------

function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomFloat(min: number, max: number): number {
  return Math.random() * (max - min) + min;
}

function randomBool(probability: number): boolean {
  return Math.random() < probability;
}

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------

/**
 * Simulate human "thinking" time before responding.
 * Returns a promise that resolves after a random delay.
 */
export async function simulateThinkTime(): Promise<void> {
  const delay = randomInt(config.minThinkTimeMs, config.maxThinkTimeMs);
  logger.debug('Anti-detect: think time', { delayMs: delay });
  await new Promise(r => setTimeout(r, delay));
}

/**
 * Simulate human typing speed for a given text length.
 * Returns the delay to wait before the message is "finished".
 */
export function simulateTypingDelay(text: string): number {
  const cps = randomFloat(config.typingSpeedCps.min, config.typingSpeedCps.max);
  const charCount = text.length;
  // Humans don't type at a constant rate; add extra variance
  const baseTime = (charCount / cps) * 1000;
  const variance = randomFloat(0.2, 0.5) * baseTime; // 20-50% extra
  return Math.round(baseTime + variance);
}

/**
 * Occasionally insert an idle pause (random duration) to
 * simulate the user stepping away from their phone.
 */
export async function maybeIdlePause(): Promise<void> {
  if (!randomBool(config.idlePauseProbability)) return;
  const delay = randomInt(config.idlePauseMs.min, config.idlePauseMs.max);
  logger.debug('Anti-detect: idle pause', { delayMs: delay });
  await new Promise(r => setTimeout(r, delay));
}

/**
 * Simulate a "read receipt" delay — the human delay between
 * receiving a message and starting to respond.
 */
export async function simulateReadReceiptDelay(): Promise<void> {
  if (!randomBool(config.readReceiptDelayProbability)) return;
  const delay = randomInt(config.readReceiptDelayMs.min, config.readReceiptDelayMs.max);
  logger.debug('Anti-detect: read receipt delay', { delayMs: delay });
  await new Promise(r => setTimeout(r, delay));
}

// ---------------------------------------------------------------------------
// Poll jitter
// ---------------------------------------------------------------------------

/**
 * Apply jitter to a base polling interval.
 * This prevents the bot from polling at exact fixed intervals.
 */
export function jitterInterval(baseMs: number): number {
  const jitter = baseMs * config.pollJitterFraction;
  return Math.round(baseMs + randomFloat(-jitter, jitter));
}

// ---------------------------------------------------------------------------
// Session rotation
// ---------------------------------------------------------------------------

/**
 * Returns a random User-Agent header from the configured list.
 * Rotating UA headers makes the bot harder to fingerprint at the HTTP level.
 */
export function getRandomUserAgent(): string {
  return config.userAgents[randomInt(0, config.userAgents.length - 1)];
}

/**
 * Add jitter to API request timing.
 * Returns extra delay in ms to add before a request.
 */
export function getRequestJitterMs(): number {
  // Add 0-500ms of random delay before API calls
  return randomInt(0, 500);
}

// ---------------------------------------------------------------------------
// Runtime reconfiguration
// ---------------------------------------------------------------------------

/**
 * Update anti-detect config at runtime.
 */
export function updateAntiDetectConfig(partial: Partial<AntiDetectConfig>): void {
  config = { ...config, ...partial };
  logger.info('Anti-detect config updated');
}

// ---------------------------------------------------------------------------
// Activity schedule (randomized daily schedule)
// ---------------------------------------------------------------------------

interface ActivityWindow {
  startHour: number; // 0-23
  endHour: number;   // 0-23
  activityLevel: 'high' | 'medium' | 'low'; // affects polling frequency
}

/**
 * Get the current activity window based on local time.
 * Returns an activity level that controls polling aggressiveness.
 */
export function getCurrentActivityLevel(): 'high' | 'medium' | 'low' {
  const hour = new Date().getHours();

  // Human-like activity windows (these are approximate and vary per person)
  const windows: ActivityWindow[] = [
    { startHour: 7, endHour: 9, activityLevel: 'medium' },    // Morning commute
    { startHour: 9, endHour: 12, activityLevel: 'low' },       // Work morning
    { startHour: 12, endHour: 14, activityLevel: 'high' },     // Lunch break
    { startHour: 14, endHour: 18, activityLevel: 'low' },      // Work afternoon
    { startHour: 18, endHour: 22, activityLevel: 'high' },     // Evening
    { startHour: 22, endHour: 23, activityLevel: 'medium' },   // Late night
  ];

  for (const w of windows) {
    if (hour >= w.startHour && hour < w.endHour) {
      return w.activityLevel;
    }
  }

  // Default: low activity (sleep hours: 23:00 - 7:00)
  return 'low';
}

/**
 * Returns a polling interval adjusted for the current activity level.
 */
export function getAdaptivePollInterval(baseIntervalMs: number): number {
  const level = getCurrentActivityLevel();
  let multiplier: number;
  switch (level) {
    case 'high':
      multiplier = randomFloat(0.7, 1.0);
      break;
    case 'medium':
      multiplier = randomFloat(1.0, 1.5);
      break;
    case 'low':
      multiplier = randomFloat(1.5, 3.0);
      break;
  }
  const interval = Math.round(baseIntervalMs * multiplier);
  return jitterInterval(interval);
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

export type { AntiDetectConfig };
export { DEFAULT_CONFIG };
