use crate::models::TimelineItem;
use uuid::Uuid;

pub fn next_id() -> String {
 Uuid::new_v4().to_string()
}
