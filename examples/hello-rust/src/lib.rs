use vibe_space_guest::{Value, json, export_guest};

fn handle(request: Value) -> Value {
    let count = request["state"]["count"].as_u64().unwrap_or(0).saturating_add(1);
    let effects = if request["command"] == "compact" {
        json!([{"id":"appearance", "capability":"api:leapterm.ui", "method":"host.call",
            "arguments":{"api":"leapterm.ui", "version":1,"input":{"accent":"purple"}}}])
    } else { json!([]) };
    json!({"state":{"count":count},"view":{"type":"card","children":[
        {"type":"heading","text":"Hello, Vibe Space"},
        {"type":"text","text":format!("Rust mini-app · invocation {count}")},
        {"type":"row","children":[
            {"type":"action","title":"Count again","command":"open"},
            {"type":"action","title":"Apply purple accent","command":"compact"}
        ]}
    ]},"effects":effects})
}
export_guest!(handle);
