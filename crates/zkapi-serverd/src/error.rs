//! Server error types.

use thiserror::Error;

/// Errors that can occur during server-side request processing.
#[derive(Error, Debug)]
pub enum ServerError {
    /// Emitted before a native request nullifier is reserved. Existing bound
    /// requests retain their quote and never return this during recovery.
    #[error("native billing quote expired before request acceptance")]
    NativeQuoteExpired,

    /// A newer finalized oracle round exists before request acceptance.
    /// Recover this exact request before preparing another proof.
    #[error("native billing quote superseded before request acceptance")]
    NativeQuoteSuperseded,

    #[error("invalid proof: {0}")]
    InvalidProof(String),

    #[error("stale root: latest is {latest_root}")]
    StaleRoot { latest_root: String },

    #[error("replayed nullifier")]
    Replay,

    #[error("note expired")]
    NoteExpired,

    #[error("internal error: {0}")]
    Internal(String),

    #[error("capacity exhausted")]
    CapacityExhausted,

    #[error("nullifier already used")]
    NullifierUsed,

    #[error("database error: {0}")]
    Database(String),

    #[error("invalid request: {0}")]
    InvalidRequest(String),

    #[error("protocol mismatch: {0}")]
    ProtocolMismatch(String),

    #[error("OpenRouter lease is already active or awaiting settlement")]
    LeasePending,

    #[error(
        "OpenRouter lease settlement is still pending; retry after {retry_after_seconds} seconds"
    )]
    LeaseSettlementPending { retry_after_seconds: u64 },

    #[error("OA org rejected the key allowance or duration; recover the saved request")]
    OaKeyPolicyRejected,

    #[error(
        "OA org key issuance was rate limited ({reason}); retry after {retry_after_seconds} seconds"
    )]
    OaRateLimited {
        reason: String,
        retry_after_seconds: u64,
    },
}

impl ServerError {
    /// Return a machine-readable error code string for the error.
    pub fn error_code(&self) -> &str {
        match self {
            ServerError::NativeQuoteExpired => "native_quote_expired",
            ServerError::NativeQuoteSuperseded => "native_quote_superseded",
            ServerError::InvalidProof(_) => "invalid_proof",
            ServerError::StaleRoot { .. } => "stale_root",
            ServerError::Replay => "replay",
            ServerError::NoteExpired => "note_expired",
            ServerError::Internal(_) => "internal_error",
            ServerError::CapacityExhausted => "capacity_exhausted",
            ServerError::NullifierUsed => "nullifier_used",
            ServerError::Database(_) => "database_error",
            ServerError::InvalidRequest(_) => "invalid_request",
            ServerError::ProtocolMismatch(_) => "protocol_mismatch",
            ServerError::LeasePending => "lease_pending",
            ServerError::LeaseSettlementPending { .. } => "lease_settlement_pending",
            ServerError::OaKeyPolicyRejected => "oa_key_policy_rejected",
            ServerError::OaRateLimited { reason, .. } => reason,
        }
    }

    /// Whether the client should retry the request.
    pub fn is_retriable(&self) -> bool {
        match self {
            ServerError::NativeQuoteExpired => true,
            ServerError::NativeQuoteSuperseded => false,
            ServerError::StaleRoot { .. } => true,
            ServerError::Internal(_) => true,
            ServerError::Database(_) => true,
            ServerError::InvalidProof(_) => false,
            ServerError::Replay => false,
            ServerError::NoteExpired => false,
            ServerError::CapacityExhausted => false,
            ServerError::NullifierUsed => false,
            ServerError::InvalidRequest(_) => false,
            ServerError::ProtocolMismatch(_) => false,
            ServerError::LeasePending => true,
            ServerError::LeaseSettlementPending { .. } => true,
            ServerError::OaKeyPolicyRejected => false,
            ServerError::OaRateLimited { .. } => true,
        }
    }
}
