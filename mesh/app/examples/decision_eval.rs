//! Synthetic completion checks; run on studio with a separate decision config and provider credential.
use anyhow::{Result, Context};
use serde_json::{Value, json};
use stillfail_app::decision::{DecisionConfig, completion_question, decide};

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<_> = std::env::args().collect();
    anyhow::ensure!(args.len() == 3, "usage: decision_eval <decision-config.json> <cases.jsonl>");
    let config: DecisionConfig = serde_json::from_str(&std::fs::read_to_string(&args[1])?)?;
    config.validate()?;
    let cases = std::fs::read_to_string(&args[2])?;
    let (mut total, mut correct, mut errors, mut false_done) = (0,0,0,0);
    for line in cases.lines().filter(|l| !l.trim().is_empty()) {
        let case: Value = serde_json::from_str(line)?;
        let expected = case["expected"].as_str().context("case expected missing")?;
        let state = case.get("state").context("case state missing")?;
        total += 1;
        let start = std::time::Instant::now();
        match decide(&config, &completion_question(), state).await {
            Ok(result) => {
                correct += u32::from(result.selected == expected);
                let accepted = result.accepts_completion(config.threshold);
                false_done += u32::from(accepted && expected != "complete");
                println!("{}", json!({"id":case["id"],"expected":expected,"result":result,
                    "accepted":accepted,"elapsedMs":start.elapsed().as_millis()}));
            }
            Err(e) => {
                errors += 1;
                println!("{}",json!({"id":case["id"],"error":e.to_string(),"elapsedMs":start.elapsed().as_millis()}));
            }
        }
    }
    println!("{}", json!({"summary":{"cases":total,"correct":correct,"errors":errors,"falseDone":false_done}}));
    anyhow::ensure!(total > 0 && errors == 0 && false_done == 0, "evaluation has missing checks or false completion; inspect its output");
    Ok(())
}
