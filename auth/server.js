/**
 * =============================================================
 * RealE Linux — SPL Token Gate Auth Server
 * Copyright (c) Joe Wease, RealE
 * =============================================================
 *
 * Flow:
 *  1. User visits portal, connects Phantom/Solflare wallet (client-side)
 *  2. Client sends wallet pubkey + signed message to POST /auth/verify
 *  3. Server checks SPL token balance on-chain
 *  4. If balance >= REQUIRED_AMOUNT → issues JWT session cookie
 *  5. Nginx /desktop/ route validates cookie via /_auth → GET /validate
 */

require("dotenv").config();
const crypto = require("crypto");
const express = require("express");
const jwt = require("jsonwebtoken");
const cors = require("cors");
const cookieParser = require("cookie-parser");
const nacl = require("tweetnacl");
const {
  Connection,
  PublicKey,
  clusterApiUrl,
} = require("@solana/web3.js");
const {
  getAccount,
  getAssociatedTokenAddress,
  TOKEN_PROGRAM_ID,
} = require("@solana/spl-token");

const app = express();
app.use(express.json());
app.use(cookieParser());
app.use(cors({ origin: process.env.ALLOWED_ORIGIN || "*" }));

// ── Config ───────────────────────────────────────────────────
const CONFIG = {
  // Solana RPC endpoint (mainnet-beta | devnet | custom)
  RPC_ENDPOINT: process.env.SOLANA_RPC || clusterApiUrl("mainnet-beta"),

  // Your SPL token mint address — REPLACE with your RealE token mint
  TOKEN_MINT: process.env.REALE_TOKEN_MINT || "YOUR_SPL_TOKEN_MINT_ADDRESS",

  // Minimum token balance required (in raw units — account for decimals)
  // e.g., if token has 6 decimals, 1 token = 1_000_000
  REQUIRED_AMOUNT: BigInt(process.env.REQUIRED_TOKEN_AMOUNT || "1000000"),

  // JWT signing secret — set a strong random value in .env
  JWT_SECRET: process.env.JWT_SECRET || "CHANGE_THIS_SECRET_IN_PRODUCTION",

  // Session duration
  SESSION_HOURS: parseInt(process.env.SESSION_HOURS || "4"),

  // Port
  PORT: parseInt(process.env.AUTH_PORT || "3000"),
};

const solanaConnection = new Connection(CONFIG.RPC_ENDPOINT, "confirmed");

// ── Nonce Store ─────────────────────────────────────────────
// In-memory store for signature challenges. Each nonce expires after 5 minutes.
// For multi-instance deployments, replace with Redis or similar.
const NONCE_TTL_MS = 5 * 60 * 1000;
const nonceStore = new Map(); // wallet → { nonce, message, expiresAt }

function generateNonce() {
  return crypto.randomBytes(32).toString("base64url");
}

function createChallenge(wallet) {
  const nonce = generateNonce();
  const message = `RealE Linux Access\n\nWallet: ${wallet}\nNonce: ${nonce}\nTimestamp: ${new Date().toISOString()}`;
  const expiresAt = Date.now() + NONCE_TTL_MS;
  nonceStore.set(wallet, { nonce, message, expiresAt });
  return message;
}

function consumeChallenge(wallet) {
  const entry = nonceStore.get(wallet);
  if (!entry) return null;
  nonceStore.delete(wallet);
  if (Date.now() > entry.expiresAt) return null;
  return entry.message;
}

// Periodically clean expired nonces (every 60s)
setInterval(() => {
  const now = Date.now();
  for (const [key, val] of nonceStore) {
    if (now > val.expiresAt) nonceStore.delete(key);
  }
}, 60_000).unref();

function verifySignature(walletAddress, signature, message) {
  const walletPubkey = new PublicKey(walletAddress);
  const messageBytes = new TextEncoder().encode(message);
  const signatureBytes = Buffer.from(signature, "base64");
  return nacl.sign.detached.verify(
    messageBytes,
    signatureBytes,
    walletPubkey.toBytes()
  );
}

// ── Helpers ──────────────────────────────────────────────────
function issueSession(wallet) {
  return jwt.sign(
    {
      wallet,
      product: "reale-linux",
      iss: "reale.one",
    },
    CONFIG.JWT_SECRET,
    { expiresIn: `${CONFIG.SESSION_HOURS}h` }
  );
}

async function checkTokenBalance(walletAddress) {
  try {
    const walletPubkey = new PublicKey(walletAddress);
    const mintPubkey = new PublicKey(CONFIG.TOKEN_MINT);

    const ata = await getAssociatedTokenAddress(mintPubkey, walletPubkey);
    const account = await getAccount(solanaConnection, ata, "confirmed", TOKEN_PROGRAM_ID);

    return {
      balance: account.amount,
      hasAccess: account.amount >= CONFIG.REQUIRED_AMOUNT,
    };
  } catch (err) {
    // Account doesn't exist = 0 balance
    if (err.name === "TokenAccountNotFoundError") {
      return { balance: BigInt(0), hasAccess: false };
    }
    throw err;
  }
}

function validateWalletAddress(address) {
  try {
    new PublicKey(address);
    return true;
  } catch {
    return false;
  }
}

// ── Routes ───────────────────────────────────────────────────

/**
 * GET /health
 * Health check for RunPod / container orchestration
 */
app.get("/health", (req, res) => {
  res.json({ status: "ok", service: "reale-auth", version: "1.0.0" });
});

/**
 * GET /auth/nonce
 * Request a challenge message for the wallet to sign.
 * Query: ?wallet=SoLaNaWaLlEtAdDrEsS
 * Returns: { message: "..." }
 */
app.get("/auth/nonce", (req, res) => {
  const { wallet } = req.query;

  if (!wallet || !validateWalletAddress(wallet)) {
    return res.status(400).json({ error: "Invalid wallet address" });
  }

  const message = createChallenge(wallet);
  res.json({ message });
});

/**
 * POST /auth/check
 * Check token balance without issuing session (for UI feedback)
 * Body: { wallet: "SoLaNaWaLlEtAdDrEsS" }
 */
app.post("/auth/check", async (req, res) => {
  const { wallet } = req.body;

  if (!wallet || !validateWalletAddress(wallet)) {
    return res.status(400).json({ error: "Invalid wallet address" });
  }

  try {
    const { balance, hasAccess } = await checkTokenBalance(wallet);
    res.json({
      wallet,
      balance: balance.toString(),
      required: CONFIG.REQUIRED_AMOUNT.toString(),
      hasAccess,
    });
  } catch (err) {
    console.error("[check]", err.message);
    res.status(500).json({ error: "RPC error — try again" });
  }
});

/**
 * POST /auth/verify
 * Main gate — verify wallet signature + token balance, then issue session.
 *
 * Body: { wallet: "...", signature: "<base64>", message: "..." }
 *
 * The client must first GET /auth/nonce?wallet=... to obtain a challenge
 * message, sign it with the wallet's private key, then POST the wallet,
 * base64-encoded signature, and original message here.
 */
app.post("/auth/verify", async (req, res) => {
  const { wallet, signature, message } = req.body;

  if (!wallet || !validateWalletAddress(wallet)) {
    return res.status(400).json({ error: "Invalid wallet address" });
  }

  if (!signature || !message) {
    return res.status(400).json({
      error: "Missing signature or message",
      hint: "First request a nonce via GET /auth/nonce?wallet=..., sign it, then POST wallet + signature + message here.",
    });
  }

  // 1. Verify the message matches a valid, unexpired server-issued nonce
  const expectedMessage = consumeChallenge(wallet);
  if (!expectedMessage) {
    return res.status(401).json({
      error: "No pending challenge or nonce expired",
      hint: "Request a new nonce via GET /auth/nonce?wallet=...",
    });
  }

  if (message !== expectedMessage) {
    return res.status(401).json({ error: "Challenge message mismatch" });
  }

  // 2. Verify the ed25519 signature proves wallet ownership
  try {
    const valid = verifySignature(wallet, signature, message);
    if (!valid) {
      return res.status(401).json({ error: "Invalid wallet signature" });
    }
  } catch (err) {
    console.error("[verify:sig]", err.message);
    return res.status(400).json({ error: "Malformed signature" });
  }

  // 3. Check SPL token balance on-chain
  try {
    const { balance, hasAccess } = await checkTokenBalance(wallet);

    if (!hasAccess) {
      return res.status(403).json({
        error: "Insufficient token balance",
        balance: balance.toString(),
        required: CONFIG.REQUIRED_AMOUNT.toString(),
        message: "You need at least the required RealE token balance to access RealE Linux.",
      });
    }

    const token = issueSession(wallet);

    // Set secure session cookie
    res.cookie("reale_session", token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      maxAge: CONFIG.SESSION_HOURS * 60 * 60 * 1000,
      path: "/",
    });

    res.json({
      success: true,
      message: "Access granted",
      wallet,
      balance: balance.toString(),
      sessionExpires: `${CONFIG.SESSION_HOURS}h`,
      redirect: "/desktop/vnc.html?autoconnect=1&resize=scale&show_dot=1",
    });
  } catch (err) {
    console.error("[verify]", err.message);
    res.status(500).json({ error: "RPC error — try again" });
  }
});

/**
 * GET /validate
 * Called internally by Nginx auth_request for /desktop/* routes.
 * Returns 200 if session is valid, 401 otherwise.
 */
app.get("/validate", (req, res) => {
  const token =
    req.headers["x-session-token"] ||
    req.cookies?.reale_session;

  if (!token) {
    return res.status(401).json({ error: "No session" });
  }

  try {
    const decoded = jwt.verify(token, CONFIG.JWT_SECRET);
    res.setHeader("X-Wallet", decoded.wallet);
    res.status(200).json({ valid: true, wallet: decoded.wallet });
  } catch (err) {
    res.status(401).json({ error: "Invalid or expired session" });
  }
});

/**
 * POST /auth/logout
 * Clear the session cookie
 */
app.post("/auth/logout", (req, res) => {
  res.clearCookie("reale_session", { path: "/" });
  res.json({ success: true, message: "Logged out" });
});

// ── Start ────────────────────────────────────────────────────
app.listen(CONFIG.PORT, "127.0.0.1", () => {
  console.log(`[RealE Auth] Listening on port ${CONFIG.PORT}`);
  console.log(`[RealE Auth] Token mint: ${CONFIG.TOKEN_MINT}`);
  console.log(`[RealE Auth] Required balance: ${CONFIG.REQUIRED_AMOUNT}`);
  console.log(`[RealE Auth] RPC: ${CONFIG.RPC_ENDPOINT}`);
});
