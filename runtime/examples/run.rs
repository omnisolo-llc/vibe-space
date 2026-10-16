use base64::{Engine as _, engine::general_purpose::STANDARD};
use vibe_space_runtime::{SignedPackage, execute, verify};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        return Err("usage: run PACKAGE TRUSTED_PUBLISHER_FILE [COMMAND]".into());
    }
    let package: SignedPackage = serde_json::from_slice(&std::fs::read(&args[1])?)?;
    let publisher: [u8; 32] = STANDARD
        .decode(std::fs::read_to_string(&args[2])?.trim())?
        .try_into()
        .map_err(|_| "invalid publisher")?;
    let (_, module) = verify(&package, &publisher)?;
    let request = serde_json::to_vec(
        &serde_json::json!({"api_version":1,"command":args.get(3).map(String::as_str).unwrap_or("open"),"arguments":{}}),
    )?;
    println!(
        "{}",
        serde_json::to_string_pretty(&execute(&module, &request)?)?
    );
    Ok(())
}
