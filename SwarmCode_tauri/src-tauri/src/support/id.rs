//! ID generation utilities - UUID-based unique identifiers for threads, messages,
//! providers, hydra heads, and other entities.

use uuid::Uuid;

/// Generate a new random UUID v4 identifier.
pub fn next_id() -> String {
    Uuid::new_v4().to_string()
}

/// Generate a new thread identifier.
pub fn next_thread_id() -> String {
    next_id()
}

/// Generate a new hydra head identifier.
pub fn next_hydra_id() -> String {
    next_id()
}

/// Generate a new message identifier.
pub fn next_message_id() -> String {
    next_id()
}

/// Generate a new provider identifier.
pub fn next_provider_id() -> String {
    next_id()
}

/// A short, human-readable identifier (base36 of a u64). Useful for display
/// in the UI alongside icons or avatars.
pub fn short_id() -> String {
    let uuid = Uuid::new_v4();
    let bytes = uuid.as_bytes();
    let num = u128::from_be_bytes(*bytes);
    format!("{:x}", num)[..8].to_string()
}

/// Validate whether a string is a well-formed UUID (any version).
pub fn is_valid_uuid(value: &str) -> bool {
    Uuid::parse_str(value).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_next_id_unique() {
        let a = next_id();
        let b = next_id();
        assert_ne!(a, b);
    }

    #[test]
    fn test_thread_message_provider_ids_unique() {
        let a = next_thread_id();
        let b = next_message_id();
        let c = next_provider_id();
        assert_ne!(a, b);
        assert_ne!(b, c);
        assert_ne!(a, c);
    }

    #[test]
    fn test_short_id_format() {
        let s = short_id();
        assert_eq!(s.chars().count(), 8);
        // should be hex only
        assert!(s.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_is_valid_uuid() {
        let valid = "550e8400-e29b-41d4-a716-446655440000";
        let invalid = "not-a-uuid";
        assert!(is_valid_uuid(valid));
        assert!(!is_valid_uuid(invalid));
    }

    #[test]
    fn test_hydra_ids_unique() {
        let a = next_hydra_id();
        let b = next_hydra_id();
        assert_ne!(a, b);
    }
}
