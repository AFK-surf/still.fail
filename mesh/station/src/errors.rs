//! The station's errors, as its log says them, sent to ember's error tracking (ember-app's ErrorReports) while the
//! config turns that on (`telemetry.errors`): what the Node part's log hook did (src/telemetry.ts).

use std::sync::{Arc, OnceLock};

use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::{Context, Layer};

/// Where errors go, once the app has made it.
pub static REPORTS: OnceLock<Arc<ember_app::telemetry::ErrorReports>> = OnceLock::new();

/// An error-level event's words: its message, and its `error` field when it has one.
#[derive(Default)]
struct Said {
    message: String,
    error: Option<String>,
    fields: Vec<String>,
}

impl Visit for Said {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        match field.name() {
            "message" => self.message = format!("{value:?}"),
            "error" => self.error = Some(format!("{value:?}")),
            other => self.fields.push(format!("{other}={value:?}")),
        }
    }
    fn record_str(&mut self, field: &Field, value: &str) {
        match field.name() {
            "message" => self.message = value.to_string(),
            "error" => self.error = Some(value.to_string()),
            other => self.fields.push(format!("{other}={value}")),
        }
    }
}

pub struct ErrorLayer;

impl<S: Subscriber> Layer<S> for ErrorLayer {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        if *event.metadata().level() != Level::ERROR {
            return;
        }
        let Some(reports) = REPORTS.get() else { return };
        let mut said = Said::default();
        event.record(&mut said);
        let log = if said.fields.is_empty() { said.message } else { format!("{} ({})", said.message, said.fields.join(", ")) };
        reports.report(&log, said.error.as_deref());
    }
}
