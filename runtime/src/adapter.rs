//! Bidirectional UI compatibility adapters, handle-resolved native IR,
//! terminal/Markdown renderers, and multi-language locale strings.

use std::collections::{BTreeMap, HashSet};

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

use crate::{Error, MAX_MESSAGE_BYTES};

const MAX_DEPTH: usize = 16;
const MAX_NODES: usize = 1024;
const SPARK_BLOCKS: &[char] = &['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// Localized UI copy for Vibe Space shells across human languages and scripts.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocaleStrings {
    pub locale: String,
    pub is_rtl: bool,
    pub vibe_space: String,
    pub wish_placeholder: String,
    pub send: String,
    pub what_host_offers: String,
    pub reads: String,
    pub shows: String,
    pub cannot: String,
    pub allow_and_add: String,
    pub update: String,
    pub cancel: String,
    pub installed: String,
    pub no_vibes_yet: String,
    pub inspect: String,
    pub share: String,
    pub delete: String,
    pub edit: String,
    pub rename: String,
    pub pause: String,
    pub resume: String,
    pub pin_to_top: String,
    pub unpin: String,
    pub revert: String,
    pub undo: String,
    pub temporary: String,
    pub pinned: String,
    pub pin_to_vibe_space: String,
    pub source_offline: String,
    pub source_revoked: String,
    pub retry: String,
    pub preview_sample: String,
    pub return_to_live: String,
    pub sealed_legend: String,
}

/// Returns localized strings for `locale` (`en`, `zh`, `ja`, `ko`, `es`, `fr`, `de`, `ar`).
pub fn locale_strings(locale: &str) -> LocaleStrings {
    let base = locale
        .trim()
        .to_ascii_lowercase()
        .split(['-', '_'])
        .next()
        .unwrap_or("en")
        .to_owned();

    match base.as_str() {
        "zh" => LocaleStrings {
            locale: "zh".into(),
            is_rtl: false,
            vibe_space: "Vibe 空间".into(),
            wish_placeholder: "我希望应用能够…".into(),
            send: "发送".into(),
            what_host_offers: "应用提供的能力".into(),
            reads: "读取".into(),
            shows: "显示".into(),
            cannot: "禁止".into(),
            allow_and_add: "允许并添加".into(),
            update: "更新".into(),
            cancel: "取消".into(),
            installed: "已安装".into(),
            no_vibes_yet: "暂无内容，许个愿吧。".into(),
            inspect: "检查".into(),
            share: "分享".into(),
            delete: "删除".into(),
            edit: "编辑".into(),
            rename: "重命名".into(),
            pause: "暂停".into(),
            resume: "恢复".into(),
            pin_to_top: "置顶".into(),
            unpin: "取消置顶".into(),
            revert: "还原".into(),
            undo: "撤销".into(),
            temporary: "临时".into(),
            pinned: "已固定".into(),
            pin_to_vibe_space: "固定到 Vibe 空间".into(),
            source_offline: "数据源离线".into(),
            source_revoked: "数据源已关闭".into(),
            retry: "重试".into(),
            preview_sample: "预览示例数据".into(),
            return_to_live: "返回实时数据".into(),
            sealed_legend: "带锁的值为密封值，由宿主绘制，Vibe 无法看见。".into(),
        },
        "ja" => LocaleStrings {
            locale: "ja".into(),
            is_rtl: false,
            vibe_space: "Vibe スペース".into(),
            wish_placeholder: "アプリへの要望を入力…".into(),
            send: "送信".into(),
            what_host_offers: "提供中の機能".into(),
            reads: "読み取り".into(),
            shows: "表示".into(),
            cannot: "不可".into(),
            allow_and_add: "許可して追加".into(),
            update: "更新".into(),
            cancel: "キャンセル".into(),
            installed: "インストール済み".into(),
            no_vibes_yet: "まだ何もありません。要望を入力してください。".into(),
            inspect: "検査".into(),
            share: "共有".into(),
            delete: "削除".into(),
            edit: "編集".into(),
            rename: "名前変更".into(),
            pause: "一時停止".into(),
            resume: "再開".into(),
            pin_to_top: "先頭に固定".into(),
            unpin: "固定解除".into(),
            revert: "元に戻す".into(),
            undo: "取り消し".into(),
            temporary: "一時的".into(),
            pinned: "固定済み".into(),
            pin_to_vibe_space: "Vibe スペースに固定".into(),
            source_offline: "データソースがオフラインです".into(),
            source_revoked: "データソースが無効です".into(),
            retry: "再試行".into(),
            preview_sample: "サンプルを表示".into(),
            return_to_live: "ライブに戻る".into(),
            sealed_legend: "鍵付きの値はシール済みで、ホストが描画し Vibe からは見えません。".into(),
        },
        "ko" => LocaleStrings {
            locale: "ko".into(),
            is_rtl: false,
            vibe_space: "Vibe 스페이스".into(),
            wish_placeholder: "원하는 기능을 입력하세요…".into(),
            send: "전송".into(),
            what_host_offers: "호스트 제공 기능".into(),
            reads: "읽기".into(),
            shows: "표시".into(),
            cannot: "제한".into(),
            allow_and_add: "허용 및 추가".into(),
            update: "업데이트".into(),
            cancel: "취소".into(),
            installed: "설치됨".into(),
            no_vibes_yet: "아직 없습니다. 요청을 입력해 보세요.".into(),
            inspect: "검사".into(),
            share: "공유".into(),
            delete: "삭제".into(),
            edit: "편집".into(),
            rename: "이름 바꾸기".into(),
            pause: "일시정지".into(),
            resume: "재개".into(),
            pin_to_top: "상단 고정".into(),
            unpin: "고정 해제".into(),
            revert: "되돌리기".into(),
            undo: "실행 취소".into(),
            temporary: "임시".into(),
            pinned: "고정됨".into(),
            pin_to_vibe_space: "Vibe 스페이스에 고정".into(),
            source_offline: "데이터 소스 오프라인".into(),
            source_revoked: "데이터 접근 꺼짐".into(),
            retry: "다시 시도".into(),
            preview_sample: "샘플 미리보기".into(),
            return_to_live: "실시간으로 돌아가기".into(),
            sealed_legend: "자물쇠가 있는 값은 봉인되어 호스트가 그리며 Vibe는 볼 수 없습니다.".into(),
        },
        "es" => LocaleStrings {
            locale: "es".into(),
            is_rtl: false,
            vibe_space: "Vibe Space".into(),
            wish_placeholder: "Me gustaría que la app…".into(),
            send: "Enviar".into(),
            what_host_offers: "Qué ofrece la app".into(),
            reads: "Lee".into(),
            shows: "Muestra".into(),
            cannot: "No puede".into(),
            allow_and_add: "Permitir y añadir".into(),
            update: "Actualizar".into(),
            cancel: "Cancelar".into(),
            installed: "Instalados".into(),
            no_vibes_yet: "Nada aquí todavía. Pide un deseo.".into(),
            inspect: "Inspeccionar".into(),
            share: "Compartir".into(),
            delete: "Eliminar".into(),
            edit: "Editar".into(),
            rename: "Renombrar".into(),
            pause: "Pausar".into(),
            resume: "Reanudar".into(),
            pin_to_top: "Fijar arriba".into(),
            unpin: "Desfijar".into(),
            revert: "Revertir".into(),
            undo: "Deshacer".into(),
            temporary: "Temporal".into(),
            pinned: "Fijado".into(),
            pin_to_vibe_space: "Fijar en Vibe Space".into(),
            source_offline: "Fuente sin conexión".into(),
            source_revoked: "Acceso desactivado".into(),
            retry: "Reintentar".into(),
            preview_sample: "Ver muestra".into(),
            return_to_live: "Volver a en vivo".into(),
            sealed_legend: "Los valores con candado están sellados. El anfitrión los dibuja; el vibe nunca los ve.".into(),
        },
        "fr" => LocaleStrings {
            locale: "fr".into(),
            is_rtl: false,
            vibe_space: "Vibe Space".into(),
            wish_placeholder: "Je voudrais que l’app…".into(),
            send: "Envoyer".into(),
            what_host_offers: "Ce que l’app propose".into(),
            reads: "Lit".into(),
            shows: "Affiche".into(),
            cannot: "Ne peut pas".into(),
            allow_and_add: "Autoriser et ajouter".into(),
            update: "Mettre à jour".into(),
            cancel: "Annuler".into(),
            installed: "Installés".into(),
            no_vibes_yet: "Rien ici pour l’instant. Faites un vœu.".into(),
            inspect: "Inspecter".into(),
            share: "Partager".into(),
            delete: "Supprimer".into(),
            edit: "Modifier".into(),
            rename: "Renommer".into(),
            pause: "Mettre en pause".into(),
            resume: "Reprendre".into(),
            pin_to_top: "Épingler en haut".into(),
            unpin: "Désépingler".into(),
            revert: "Rétablir".into(),
            undo: "Annuler".into(),
            temporary: "Temporaire".into(),
            pinned: "Épinglé".into(),
            pin_to_vibe_space: "Épingler dans Vibe Space".into(),
            source_offline: "Source hors ligne".into(),
            source_revoked: "Accès désactivé".into(),
            retry: "Réessayer".into(),
            preview_sample: "Aperçu d’exemple".into(),
            return_to_live: "Revenir au direct".into(),
            sealed_legend: "Les valeurs avec cadenas sont scellées. L’hôte les affiche ; le vibe ne les voit jamais.".into(),
        },
        "de" => LocaleStrings {
            locale: "de".into(),
            is_rtl: false,
            vibe_space: "Vibe Space".into(),
            wish_placeholder: "Ich wünsche mir…".into(),
            send: "Senden".into(),
            what_host_offers: "Was die App anbietet".into(),
            reads: "Liest".into(),
            shows: "Zeigt".into(),
            cannot: "Kann nicht".into(),
            allow_and_add: "Erlauben & hinzufügen".into(),
            update: "Aktualisieren".into(),
            cancel: "Abbrechen".into(),
            installed: "Installiert".into(),
            no_vibes_yet: "Noch nichts hier. Äußere einen Wunsch.".into(),
            inspect: "Prüfen".into(),
            share: "Teilen".into(),
            delete: "Löschen".into(),
            edit: "Bearbeiten".into(),
            rename: "Umbenennen".into(),
            pause: "Pausieren".into(),
            resume: "Fortsetzen".into(),
            pin_to_top: "Oben anheften".into(),
            unpin: "Lösen".into(),
            revert: "Zurücksetzen".into(),
            undo: "Rückgängig".into(),
            temporary: "Temporär".into(),
            pinned: "Angeheftet".into(),
            pin_to_vibe_space: "In Vibe Space anheften".into(),
            source_offline: "Datenquelle offline".into(),
            source_revoked: "Zugriff deaktiviert".into(),
            retry: "Erneut versuchen".into(),
            preview_sample: "Beispieldaten".into(),
            return_to_live: "Zurück zu Live".into(),
            sealed_legend: "Werte mit Schloss sind versiegelt. Der Host zeichnet sie; das Vibe sieht sie nie.".into(),
        },
        "ar" => LocaleStrings {
            locale: "ar".into(),
            is_rtl: true,
            vibe_space: "مساحة Vibe".into(),
            wish_placeholder: "أتمنى لو يقوم التطبيق بـ…".into(),
            send: "إرسال".into(),
            what_host_offers: "ما يقدمه التطبيق".into(),
            reads: "يقرأ".into(),
            shows: "يعرض".into(),
            cannot: "لا يمكنه".into(),
            allow_and_add: "سماح وإضافة".into(),
            update: "تحديث".into(),
            cancel: "إلغاء".into(),
            installed: "المثبتة".into(),
            no_vibes_yet: "لا يوجد شيء هنا بعد. اطلب ميزة.".into(),
            inspect: "فحص".into(),
            share: "مشاركة".into(),
            delete: "حذف".into(),
            edit: "تعديل".into(),
            rename: "إعادة تسمية".into(),
            pause: "إيقاف مؤقت".into(),
            resume: "استئناف".into(),
            pin_to_top: "تثبيت في الأعلى".into(),
            unpin: "إلغاء التثبيت".into(),
            revert: "استعادة".into(),
            undo: "تراجع".into(),
            temporary: "مؤقت".into(),
            pinned: "مثبت".into(),
            pin_to_vibe_space: "تثبيت في مساحة Vibe".into(),
            source_offline: "مصدر البيانات غير متصل".into(),
            source_revoked: "تم إيقاف الوصول للمصدر".into(),
            retry: "إعادة المحاولة".into(),
            preview_sample: "معاينة بيانات تجريبية".into(),
            return_to_live: "العودة للبث المباشر".into(),
            sealed_legend: "القيم ذات القفل مختومة؛ يعرضها المضيف ولا يراها البرنامج أبداً.".into(),
        },
        _ => LocaleStrings {
            locale: "en".into(),
            is_rtl: false,
            vibe_space: "Vibe Space".into(),
            wish_placeholder: "I wish this app would…".into(),
            send: "Send".into(),
            what_host_offers: "What this host offers".into(),
            reads: "Reads".into(),
            shows: "Shows".into(),
            cannot: "Cannot".into(),
            allow_and_add: "Allow and add".into(),
            update: "Update".into(),
            cancel: "Cancel".into(),
            installed: "Installed".into(),
            no_vibes_yet: "Nothing here yet. Make a wish.".into(),
            inspect: "Inspect".into(),
            share: "Share".into(),
            delete: "Delete".into(),
            edit: "Edit".into(),
            rename: "Rename".into(),
            pause: "Pause".into(),
            resume: "Resume".into(),
            pin_to_top: "Pin to top".into(),
            unpin: "Unpin".into(),
            revert: "Revert".into(),
            undo: "Undo".into(),
            temporary: "Temporary".into(),
            pinned: "Pinned".into(),
            pin_to_vibe_space: "Pin to Vibe Space".into(),
            source_offline: "Source offline".into(),
            source_revoked: "Source turned off".into(),
            retry: "Retry".into(),
            preview_sample: "Preview sample".into(),
            return_to_live: "Return to live".into(),
            sealed_legend: "Values with a lock are sealed. The host draws them. The vibe never sees them.".into(),
        },
    }
}

/// Converts canonical VibeView, A2UI (`surfaceUpdate`/`components`), Adaptive Cards,
/// or Markdown into a validated canonical `VibeView` JSON object.
pub fn adapt_external_ui(raw: &Value) -> Result<Value, Error> {
    let encoded_len = serde_json::to_vec(raw)?.len();
    if encoded_len > MAX_MESSAGE_BYTES {
        return Err(Error::Package);
    }

    let adapted = match raw {
        Value::String(md) => adapt_markdown(md),
        Value::Object(map) => {
            if map.get("format").and_then(Value::as_str) == Some("markdown") {
                let md = map
                    .get("markdown")
                    .or_else(|| map.get("content"))
                    .and_then(Value::as_str)
                    .ok_or(Error::Package)?;
                adapt_markdown(md)
            } else if map.get("type").and_then(Value::as_str) == Some("AdaptiveCard") {
                adapt_adaptive_card(map)?
            } else if map.contains_key("surfaceUpdate") || map.contains_key("components") {
                adapt_a2ui_surface(map)?
            } else if is_a2ui_component_wrapper(map) {
                adapt_a2ui_node(raw, &BTreeMap::new(), &mut HashSet::new(), 0)?
            } else {
                normalize_canonical_node(raw, 0)?
            }
        }
        _ => return Err(Error::Package),
    };

    let mut budget = MAX_NODES;
    validate_canonical_node(&adapted, 0, &mut budget)?;
    Ok(adapted)
}

/// Resolves sealed handles across a view tree into toolkit-neutral JSON IR.
/// Unknown/forged handles resolve to `""` with `"sealed_resolved": false`.
pub fn resolve_view_tree(
    view: &Value,
    resolve_sealed: impl Fn(&str) -> Option<String>,
) -> Result<Value, Error> {
    let normalized = adapt_external_ui(view)?;
    resolve_node_recursive(&normalized, &resolve_sealed)
}

/// Renders a canonical or external UI view to plain or ANSI-colored terminal text.
pub fn render_terminal(
    view: &Value,
    resolve_sealed: impl Fn(&str) -> Option<String>,
    ansi: bool,
    width: usize,
) -> Result<String, Error> {
    let normalized = adapt_external_ui(view)?;
    let clamped_width = width.clamp(24, 160);
    let mut lines = Vec::new();
    render_terminal_node(&normalized, &resolve_sealed, ansi, clamped_width, &mut lines);
    Ok(lines.join("\n"))
}

/// Renders a canonical or external UI view to Markdown.
pub fn render_markdown(
    view: &Value,
    resolve_sealed: impl Fn(&str) -> Option<String>,
) -> Result<String, Error> {
    let normalized = adapt_external_ui(view)?;
    let mut lines = Vec::new();
    render_markdown_node(&normalized, &resolve_sealed, &mut lines);
    Ok(lines.join("\n"))
}

fn sanitize_plain_text(s: &str) -> String {
    let mut out = s.replace('\0', "");
    // Strip inline <script>...</script> blocks if present in external dialects.
    while let Some(start) = out.to_ascii_lowercase().find("<script") {
        let lower = out.to_ascii_lowercase();
        if let Some(rel_end) = lower[start..].find("</script>") {
            let end = start + rel_end + "</script>".len();
            out.replace_range(start..end, "");
        } else {
            out.truncate(start);
            break;
        }
    }
    if out.to_ascii_lowercase().contains("javascript:") {
        out = out.replace("javascript:", "").replace("JAVASCRIPT:", "");
    }
    out
}

fn try_sealed_handle(val: &Value) -> Option<&str> {
    let obj = val.as_object()?;
    if obj.len() == 1 {
        obj.get("sealed")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
    } else {
        None
    }
}

fn normalize_text_value(val: Option<&Value>) -> Value {
    match val {
        None | Some(Value::Null) => Value::String(String::new()),
        Some(v) if try_sealed_handle(v).is_some() => v.clone(),
        Some(Value::String(s)) => Value::String(sanitize_plain_text(s)),
        Some(Value::Number(n)) => Value::String(n.to_string()),
        Some(Value::Bool(b)) => Value::String(b.to_string()),
        Some(Value::Object(obj)) => {
            if let Some(lit) = obj.get("literalString").and_then(Value::as_str) {
                Value::String(sanitize_plain_text(lit))
            } else if let Some(lit) = obj.get("literal") {
                normalize_text_value(Some(lit))
            } else if let Some(inner) = obj.get("text") {
                normalize_text_value(Some(inner))
            } else {
                Value::String(String::new())
            }
        }
        _ => Value::String(String::new()),
    }
}

fn normalize_tone(val: Option<&str>) -> &'static str {
    match val.map(|s| s.to_ascii_lowercase()).as_deref() {
        Some("ok" | "good" | "success" | "positive") => "ok",
        Some("warn" | "warning" | "caution") => "warn",
        Some("danger" | "error" | "attention" | "critical") => "danger",
        _ => "default",
    }
}

fn is_safe_action_url(url: &str) -> bool {
    let trimmed = url.trim().to_ascii_lowercase();
    !trimmed.starts_with("javascript:")
        && !trimmed.starts_with("vbscript:")
        && !trimmed.starts_with("data:")
}

fn is_a2ui_component_wrapper(map: &Map<String, Value>) -> bool {
    if map.contains_key("component") {
        return true;
    }
    const A2UI_KEYS: &[&str] = &[
        "Text",
        "Heading",
        "Badge",
        "Button",
        "Card",
        "Row",
        "Column",
        "TextField",
        "CheckBox",
        "MultipleChoice",
        "ProgressBar",
        "LinearProgress",
        "Metric",
        "Stat",
        "Table",
        "Divider",
        "Sparkline",
        "Bar",
    ];
    A2UI_KEYS.iter().any(|k| map.contains_key(*k))
        || map
            .get("type")
            .and_then(Value::as_str)
            .is_some_and(|t| A2UI_KEYS.contains(&t))
}

fn adapt_a2ui_surface(map: &Map<String, Value>) -> Result<Value, Error> {
    let surface = map
        .get("surfaceUpdate")
        .and_then(Value::as_object)
        .unwrap_or(map);
    let comps = surface
        .get("components")
        .and_then(Value::as_array)
        .ok_or(Error::Package)?;

    let mut by_id: BTreeMap<String, Value> = BTreeMap::new();
    let mut first_id: Option<String> = None;
    for entry in comps {
        if let Some(obj) = entry.as_object() {
            if let Some(id) = obj.get("id").and_then(Value::as_str) {
                if first_id.is_none() {
                    first_id = Some(id.to_owned());
                }
                by_id.insert(id.to_owned(), entry.clone());
            }
        }
    }

    if let Some(root_id) = surface
        .get("root")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .or_else(|| by_id.contains_key("root").then(|| "root".to_owned()))
        .or(first_id)
    {
        if let Some(root_val) = by_id.get(&root_id) {
            return adapt_a2ui_node(root_val, &by_id, &mut HashSet::new(), 0);
        }
    }

    let mut children = Vec::new();
    for entry in comps {
        children.push(adapt_a2ui_node(entry, &by_id, &mut HashSet::new(), 1)?);
    }
    Ok(json!({ "type": "column", "children": children }))
}

fn adapt_a2ui_node(
    raw: &Value,
    by_id: &BTreeMap<String, Value>,
    visiting: &mut HashSet<String>,
    depth: usize,
) -> Result<Value, Error> {
    if depth > MAX_DEPTH {
        return Err(Error::Package);
    }
    if let Some(ref_id) = raw.as_str() {
        if !visiting.insert(ref_id.to_owned()) {
            return Err(Error::Package);
        }
        let target = by_id.get(ref_id).ok_or(Error::Package)?;
        let res = adapt_a2ui_node(target, by_id, visiting, depth);
        visiting.remove(ref_id);
        return res;
    }

    let obj = raw.as_object().ok_or(Error::Package)?;
    let comp = obj.get("component").and_then(Value::as_object).unwrap_or(obj);

    let (kind, props): (&str, &Map<String, Value>) =
        if let Some(t) = comp.get("type").and_then(Value::as_str) {
            (t, comp)
        } else if let Some((k, v)) = comp
            .iter()
            .find(|(k, v)| v.is_object() && k.chars().next().is_some_and(|c| c.is_ascii_uppercase()))
        {
            (k.as_str(), v.as_object().ok_or(Error::Package)?)
        } else {
            return normalize_canonical_node(raw, depth);
        };

    let tone = normalize_tone(props.get("tone").and_then(Value::as_str));

    match kind {
        "Column" | "Row" | "Card" => {
            let out_type = kind.to_ascii_lowercase();
            let raw_children = props
                .get("children")
                .and_then(|c| {
                    c.as_array()
                        .or_else(|| c.get("explicitList").and_then(Value::as_array))
                })
                .cloned()
                .unwrap_or_default();
            let mut out_children = Vec::with_capacity(raw_children.len());
            for child in raw_children {
                out_children.push(adapt_a2ui_node(&child, by_id, visiting, depth + 1)?);
            }
            if out_children.is_empty() {
                if let Some(child_ref) = props.get("child") {
                    out_children.push(adapt_a2ui_node(child_ref, by_id, visiting, depth + 1)?);
                }
            }
            Ok(json!({ "type": out_type, "children": out_children }))
        }
        "Heading" => Ok(json!({
            "type": "heading",
            "text": normalize_text_value(props.get("text").or_else(|| props.get("title")))
        })),
        "Text" => {
            let hint = props
                .get("usageHint")
                .and_then(Value::as_str)
                .unwrap_or("");
            if hint.starts_with('h') {
                Ok(json!({
                    "type": "heading",
                    "text": normalize_text_value(props.get("text"))
                }))
            } else {
                Ok(json!({
                    "type": "text",
                    "text": normalize_text_value(props.get("text")),
                    "tone": tone
                }))
            }
        }
        "Badge" => Ok(json!({
            "type": "badge",
            "text": normalize_text_value(props.get("text").or_else(|| props.get("label"))),
            "tone": tone
        })),
        "Metric" | "Stat" => Ok(json!({
            "type": "stat",
            "label": normalize_text_value(props.get("label")),
            "value": normalize_text_value(props.get("value")),
            "tone": tone
        })),
        "Bar" | "ProgressBar" | "LinearProgress" => Ok(json!({
            "type": "bar",
            "label": normalize_text_value(props.get("label").or_else(|| props.get("title"))),
            "value": props.get("value").and_then(Value::as_f64).unwrap_or(0.0),
            "max": props.get("max").and_then(Value::as_f64).unwrap_or(1.0),
            "caption": normalize_text_value(props.get("caption")),
            "tone": tone
        })),
        "Sparkline" => Ok(json!({
            "type": "sparkline",
            "values": props.get("values").cloned().unwrap_or_else(|| json!([])),
            "tone": tone
        })),
        "Button" => {
            let cmd = props
                .get("action")
                .and_then(|a| a.get("name").or(Some(a)))
                .and_then(Value::as_str)
                .or_else(|| props.get("command").and_then(Value::as_str))
                .unwrap_or("submit");
            let text = normalize_text_value(
                props
                    .get("label")
                    .or_else(|| props.get("text"))
                    .or_else(|| props.get("child").and_then(|c| c.get("text"))),
            );
            Ok(json!({
                "type": "button",
                "text": text,
                "command": sanitize_plain_text(cmd),
                "tone": tone
            }))
        }
        "TextField" => Ok(json!({
            "type": "input",
            "id": sanitize_plain_text(props.get("id").and_then(Value::as_str).unwrap_or("input")),
            "label": normalize_text_value(props.get("label")),
            "value": normalize_text_value(props.get("text").or_else(|| props.get("value")))
        })),
        "CheckBox" => Ok(json!({
            "type": "checkbox",
            "id": sanitize_plain_text(props.get("id").and_then(Value::as_str).unwrap_or("check")),
            "label": normalize_text_value(props.get("label")),
            "value": props.get("value").and_then(Value::as_bool).unwrap_or(false)
        })),
        "MultipleChoice" => {
            let opts = props
                .get("options")
                .or_else(|| props.get("selections"))
                .cloned()
                .unwrap_or_else(|| json!([]));
            Ok(json!({
                "type": "option_group",
                "id": sanitize_plain_text(props.get("id").and_then(Value::as_str).unwrap_or("choice")),
                "label": normalize_text_value(props.get("label")),
                "options": opts
            }))
        }
        "Table" => Ok(json!({
            "type": "table",
            "headers": props.get("headers").cloned().unwrap_or_else(|| json!([])),
            "rows": props.get("rows").cloned().unwrap_or_else(|| json!([]))
        })),
        "Divider" => Ok(json!({ "type": "divider" })),
        _ => Err(Error::Package),
    }
}

fn adapt_adaptive_card(card: &Map<String, Value>) -> Result<Value, Error> {
    let mut children = Vec::new();
    if let Some(body) = card.get("body").and_then(Value::as_array) {
        for item in body {
            children.push(adapt_adaptive_element(item, 1)?);
        }
    }
    if let Some(actions) = card.get("actions").and_then(Value::as_array) {
        if !actions.is_empty() {
            let mut action_row = Vec::new();
            for act in actions {
                if let Some(btn) = adapt_adaptive_action(act) {
                    action_row.push(btn);
                }
            }
            if !action_row.is_empty() {
                children.push(json!({ "type": "row", "children": action_row }));
            }
        }
    }
    Ok(json!({ "type": "column", "children": children }))
}

fn adapt_adaptive_action(act: &Value) -> Option<Value> {
    let obj = act.as_object()?;
    let act_type = obj.get("type").and_then(Value::as_str).unwrap_or("");
    if act_type == "Action.OpenUrl" {
        let url = obj.get("url").and_then(Value::as_str).unwrap_or("");
        if !is_safe_action_url(url) {
            return None;
        }
    }
    let title = normalize_text_value(obj.get("title"));
    let cmd = obj
        .get("verb")
        .or_else(|| obj.get("id"))
        .and_then(Value::as_str)
        .unwrap_or(if act_type.is_empty() { "submit" } else { act_type });
    let mut node = json!({
        "type": "button",
        "text": title,
        "command": sanitize_plain_text(cmd),
        "tone": normalize_tone(obj.get("style").and_then(Value::as_str))
    });
    if let Some(data) = obj.get("data") {
        if data.is_object() {
            node.as_object_mut()
                .expect("object")
                .insert("args".into(), data.clone());
        }
    }
    Some(node)
}

fn adapt_adaptive_element(elem: &Value, depth: usize) -> Result<Value, Error> {
    if depth > MAX_DEPTH {
        return Err(Error::Package);
    }
    let obj = elem.as_object().ok_or(Error::Package)?;
    let kind = obj.get("type").and_then(Value::as_str).ok_or(Error::Package)?;
    match kind {
        "TextBlock" => {
            let style = obj.get("style").and_then(Value::as_str).unwrap_or("");
            let size = obj.get("size").and_then(Value::as_str).unwrap_or("");
            let weight = obj.get("weight").and_then(Value::as_str).unwrap_or("");
            let text_val = normalize_text_value(obj.get("text"));
            if style.eq_ignore_ascii_case("heading")
                || size.eq_ignore_ascii_case("large")
                || size.eq_ignore_ascii_case("extraLarge")
            {
                Ok(json!({ "type": "heading", "text": text_val }))
            } else {
                Ok(json!({
                    "type": "text",
                    "text": text_val,
                    "strong": weight.eq_ignore_ascii_case("bolder"),
                    "tone": normalize_tone(obj.get("color").and_then(Value::as_str))
                }))
            }
        }
        "Container" => {
            let items = obj
                .get("items")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let mut children = Vec::with_capacity(items.len());
            for item in items {
                children.push(adapt_adaptive_element(&item, depth + 1)?);
            }
            Ok(json!({ "type": "card", "children": children }))
        }
        "ColumnSet" => {
            let cols = obj
                .get("columns")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let mut children = Vec::with_capacity(cols.len());
            for col in cols {
                children.push(adapt_adaptive_element(&col, depth + 1)?);
            }
            Ok(json!({ "type": "row", "children": children }))
        }
        "Column" => {
            let items = obj
                .get("items")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let mut children = Vec::with_capacity(items.len());
            for item in items {
                children.push(adapt_adaptive_element(&item, depth + 1)?);
            }
            Ok(json!({ "type": "column", "children": children }))
        }
        "FactSet" => {
            let facts = obj
                .get("facts")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let mut rows = Vec::with_capacity(facts.len());
            for f in facts {
                if let Some(fo) = f.as_object() {
                    rows.push(json!([
                        normalize_text_value(fo.get("title")),
                        normalize_text_value(fo.get("value"))
                    ]));
                }
            }
            Ok(json!({
                "type": "table",
                "headers": ["Field", "Value"],
                "rows": rows
            }))
        }
        "Input.Text" => Ok(json!({
            "type": "input",
            "id": sanitize_plain_text(obj.get("id").and_then(Value::as_str).unwrap_or("input")),
            "label": normalize_text_value(obj.get("label").or_else(|| obj.get("placeholder"))),
            "value": normalize_text_value(obj.get("value"))
        })),
        "Input.Toggle" => Ok(json!({
            "type": "checkbox",
            "id": sanitize_plain_text(obj.get("id").and_then(Value::as_str).unwrap_or("toggle")),
            "label": normalize_text_value(obj.get("title")),
            "value": obj.get("value").and_then(Value::as_str) == Some("true")
        })),
        "Input.ChoiceSet" => {
            let choices = obj
                .get("choices")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let opts: Vec<Value> = choices
                .into_iter()
                .filter_map(|c| {
                    let co = c.as_object()?;
                    Some(json!({
                        "label": normalize_text_value(co.get("title")),
                        "value": normalize_text_value(co.get("value"))
                    }))
                })
                .collect();
            Ok(json!({
                "type": "option_group",
                "id": sanitize_plain_text(obj.get("id").and_then(Value::as_str).unwrap_or("choice")),
                "label": normalize_text_value(obj.get("label")),
                "options": opts
            }))
        }
        "Action.Submit" | "Action.Execute" | "Action.OpenUrl" => {
            adapt_adaptive_action(elem).ok_or(Error::Package)
        }
        "ActionSet" => {
            let actions = obj
                .get("actions")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            let btns: Vec<Value> = actions.iter().filter_map(adapt_adaptive_action).collect();
            Ok(json!({ "type": "row", "children": btns }))
        }
        _ => Err(Error::Package),
    }
}

fn adapt_markdown(markdown: &str) -> Value {
    let cleaned = sanitize_plain_text(markdown);
    let mut children = Vec::new();
    let lines: Vec<&str> = cleaned.lines().collect();
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i].trim();
        if line.is_empty() {
            i += 1;
            continue;
        }
        if line == "---" || line == "***" {
            children.push(json!({ "type": "divider" }));
            i += 1;
            continue;
        }
        if let Some(heading) = line
            .strip_prefix("### ")
            .or_else(|| line.strip_prefix("## "))
            .or_else(|| line.strip_prefix("# "))
        {
            children.push(json!({ "type": "heading", "text": heading.trim() }));
            i += 1;
            continue;
        }
        if line.starts_with('|') && i + 1 < lines.len() && lines[i + 1].trim().starts_with('|') {
            let headers: Vec<Value> = line
                .trim_matches('|')
                .split('|')
                .map(|c| json!(c.trim()))
                .collect();
            i += 2; // skip header + separator line
            let mut rows = Vec::new();
            while i < lines.len() && lines[i].trim().starts_with('|') {
                let row: Vec<Value> = lines[i]
                    .trim()
                    .trim_matches('|')
                    .split('|')
                    .map(|c| json!(c.trim()))
                    .collect();
                rows.push(Value::Array(row));
                i += 1;
            }
            children.push(json!({ "type": "table", "headers": headers, "rows": rows }));
            continue;
        }
        let text = line.strip_prefix("- ").or_else(|| line.strip_prefix("* ")).unwrap_or(line);
        children.push(json!({ "type": "text", "text": text }));
        i += 1;
    }
    json!({ "type": "column", "children": children })
}

fn normalize_canonical_node(raw: &Value, depth: usize) -> Result<Value, Error> {
    if depth > MAX_DEPTH {
        return Err(Error::Package);
    }
    let obj = raw.as_object().ok_or(Error::Package)?;
    let kind = obj.get("type").and_then(Value::as_str).ok_or(Error::Package)?;
    let mut out = obj.clone();
    if kind == "action" {
        out.insert("type".into(), Value::String("button".into()));
    }
    for key in ["text", "label", "caption", "value", "title"] {
        if let Some(v) = out.get(key).cloned() {
            if key == "value" && v.is_number() && (kind == "bar" || kind == "progress") {
                continue;
            }
            if key == "value" && v.is_boolean() && kind == "checkbox" {
                continue;
            }
            out.insert(key.into(), normalize_text_value(Some(&v)));
        }
    }
    if let Some(Value::Array(children)) = out.get("children").cloned() {
        let mut next = Vec::with_capacity(children.len());
        for c in children {
            next.push(normalize_canonical_node(&c, depth + 1)?);
        }
        out.insert("children".into(), Value::Array(next));
    }
    Ok(Value::Object(out))
}

fn validate_canonical_node(node: &Value, depth: usize, budget: &mut usize) -> Result<(), Error> {
    if depth > MAX_DEPTH || *budget == 0 {
        return Err(Error::Package);
    }
    *budget -= 1;
    let obj = node.as_object().ok_or(Error::Package)?;
    let kind = obj.get("type").and_then(Value::as_str).ok_or(Error::Package)?;
    const KNOWN: &[&str] = &[
        "column",
        "row",
        "card",
        "heading",
        "text",
        "badge",
        "stat",
        "bar",
        "sparkline",
        "table",
        "divider",
        "button",
        "input",
        "checkbox",
        "option_group",
        "progress",
    ];
    if !KNOWN.contains(&kind) {
        return Err(Error::Package);
    }
    if let Some(children) = obj.get("children") {
        let arr = children.as_array().ok_or(Error::Package)?;
        for child in arr {
            validate_canonical_node(child, depth + 1, budget)?;
        }
    }
    Ok(())
}

fn resolve_text_value(
    val: Option<&Value>,
    resolve_sealed: &impl Fn(&str) -> Option<String>,
) -> (String, bool, bool) {
    let Some(v) = val else {
        return (String::new(), false, false);
    };
    if let Some(id) = try_sealed_handle(v) {
        return match resolve_sealed(id) {
            Some(real) if !real.is_empty() => (real, true, true),
            _ => (String::new(), true, false),
        };
    }
    match v {
        Value::String(s) => (s.clone(), false, false),
        Value::Number(n) => (n.to_string(), false, false),
        Value::Bool(b) => (b.to_string(), false, false),
        _ => (String::new(), false, false),
    }
}

fn resolve_node_recursive(
    node: &Value,
    resolve_sealed: &impl Fn(&str) -> Option<String>,
) -> Result<Value, Error> {
    let obj = node.as_object().ok_or(Error::Package)?;
    let mut out = obj.clone();
    let kind = obj.get("type").and_then(Value::as_str).unwrap_or("");
    let mut had_sealed = false;
    let mut all_resolved = true;

    for key in ["text", "label", "caption", "value", "title"] {
        if let Some(v) = obj.get(key) {
            if key == "value" && ((kind == "bar" || kind == "progress") && v.is_number() || kind == "checkbox" && v.is_boolean()) {
                continue;
            }
            let (resolved, is_sealed, ok) = resolve_text_value(Some(v), resolve_sealed);
            if is_sealed {
                had_sealed = true;
                all_resolved &= ok;
            }
            out.insert(key.into(), Value::String(resolved));
        }
    }

    if let Some(Value::Array(headers)) = obj.get("headers") {
        let mut resolved_headers = Vec::with_capacity(headers.len());
        for h in headers {
            let (txt, is_sealed, ok) = resolve_text_value(Some(h), resolve_sealed);
            if is_sealed {
                had_sealed = true;
                all_resolved &= ok;
            }
            resolved_headers.push(Value::String(txt));
        }
        out.insert("headers".into(), Value::Array(resolved_headers));
    }

    if let Some(Value::Array(rows)) = obj.get("rows") {
        let mut resolved_rows = Vec::with_capacity(rows.len());
        for r in rows {
            if let Some(cells) = r.as_array() {
                let mut resolved_cells = Vec::with_capacity(cells.len());
                for c in cells {
                    let (txt, is_sealed, ok) = resolve_text_value(Some(c), resolve_sealed);
                    if is_sealed {
                        had_sealed = true;
                        all_resolved &= ok;
                    }
                    resolved_cells.push(Value::String(txt));
                }
                resolved_rows.push(Value::Array(resolved_cells));
            }
        }
        out.insert("rows".into(), Value::Array(resolved_rows));
    }

    if had_sealed {
        out.insert("sealed".into(), Value::Bool(true));
        out.insert("sealed_resolved".into(), Value::Bool(all_resolved));
    }

    if let Some(Value::Array(children)) = obj.get("children") {
        let mut next = Vec::with_capacity(children.len());
        for c in children {
            next.push(resolve_node_recursive(c, resolve_sealed)?);
        }
        out.insert("children".into(), Value::Array(next));
    }

    Ok(Value::Object(out))
}

fn format_terminal_text(
    val: Option<&Value>,
    resolve_sealed: &impl Fn(&str) -> Option<String>,
) -> String {
    let (txt, is_sealed, ok) = resolve_text_value(val, resolve_sealed);
    if is_sealed {
        if ok {
            format!("🔒 {txt}")
        } else {
            String::new()
        }
    } else {
        txt
    }
}

fn ansi_wrap(ansi: bool, tone: &str, text: &str) -> String {
    if !ansi {
        return text.to_owned();
    }
    let code = match tone {
        "ok" => "\x1b[32m",
        "warn" => "\x1b[33m",
        "danger" => "\x1b[31m",
        "bold" => "\x1b[1m",
        _ => return text.to_owned(),
    };
    format!("{code}{text}\x1b[0m")
}

fn render_sparkline(values: &[Value]) -> String {
    let nums: Vec<f64> = values.iter().filter_map(Value::as_f64).filter(|v| v.is_finite()).collect();
    if nums.is_empty() {
        return String::new();
    }
    let min = nums.iter().copied().fold(f64::INFINITY, f64::min);
    let max = nums.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let span = max - min;
    nums.iter()
        .map(|v| {
            let idx = if span <= f64::EPSILON {
                3
            } else {
                (((v - min) / span) * ((SPARK_BLOCKS.len() - 1) as f64)).round() as usize
            };
            SPARK_BLOCKS[idx.min(SPARK_BLOCKS.len() - 1)]
        })
        .collect()
}

fn render_terminal_node(
    node: &Value,
    resolve_sealed: &impl Fn(&str) -> Option<String>,
    ansi: bool,
    width: usize,
    out: &mut Vec<String>,
) {
    let Some(obj) = node.as_object() else { return };
    let kind = obj.get("type").and_then(Value::as_str).unwrap_or("");
    let tone = obj.get("tone").and_then(Value::as_str).unwrap_or("default");

    match kind {
        "column" | "card" => {
            if let Some(children) = obj.get("children").and_then(Value::as_array) {
                for c in children {
                    render_terminal_node(c, resolve_sealed, ansi, width, out);
                }
            }
        }
        "row" => {
            let mut parts = Vec::new();
            if let Some(children) = obj.get("children").and_then(Value::as_array) {
                for c in children {
                    let mut sub = Vec::new();
                    render_terminal_node(c, resolve_sealed, ansi, width, &mut sub);
                    if !sub.is_empty() {
                        parts.push(sub.join(" "));
                    }
                }
            }
            if !parts.is_empty() {
                out.push(parts.join(" | "));
            }
        }
        "heading" => {
            let txt = format_terminal_text(obj.get("text"), resolve_sealed);
            out.push(ansi_wrap(ansi, "bold", &txt));
        }
        "text" => {
            let txt = format_terminal_text(obj.get("text"), resolve_sealed);
            out.push(ansi_wrap(ansi, tone, &txt));
        }
        "badge" => {
            let txt = format_terminal_text(obj.get("text"), resolve_sealed);
            out.push(ansi_wrap(ansi, tone, &format!("[{txt}]")));
        }
        "stat" => {
            let label = format_terminal_text(obj.get("label"), resolve_sealed);
            let value = format_terminal_text(obj.get("value"), resolve_sealed);
            out.push(format!("{label}: {}", ansi_wrap(ansi, tone, &value)));
        }
        "bar" | "progress" => {
            let label = format_terminal_text(obj.get("label"), resolve_sealed);
            let caption = format_terminal_text(obj.get("caption"), resolve_sealed);
            let val = obj.get("value").and_then(Value::as_f64).unwrap_or(0.0);
            let max = obj.get("max").and_then(Value::as_f64).filter(|m| *m > 0.0).unwrap_or(1.0);
            let frac = (val / max).clamp(0.0, 1.0);
            let bar_w = (width / 3).clamp(10, 28);
            let filled = (frac * (bar_w as f64)).round() as usize;
            let bar = format!("{}{}", "█".repeat(filled), "░".repeat(bar_w - filled));
            let colored_bar = ansi_wrap(ansi, tone, &bar);
            if caption.is_empty() {
                out.push(format!("{label} {colored_bar}"));
            } else {
                out.push(format!("{label} {colored_bar} {caption}"));
            }
        }
        "sparkline" => {
            if let Some(vals) = obj.get("values").and_then(Value::as_array) {
                let spark = render_sparkline(vals);
                out.push(ansi_wrap(ansi, tone, &spark));
            }
        }
        "table" => {
            if let Some(headers) = obj.get("headers").and_then(Value::as_array) {
                let hdrs: Vec<String> = headers
                    .iter()
                    .map(|h| format_terminal_text(Some(h), resolve_sealed))
                    .collect();
                out.push(hdrs.join(" | "));
                out.push("-".repeat(width.min(48)));
            }
            if let Some(rows) = obj.get("rows").and_then(Value::as_array) {
                for r in rows {
                    if let Some(cells) = r.as_array() {
                        let line: Vec<String> = cells
                            .iter()
                            .map(|c| format_terminal_text(Some(c), resolve_sealed))
                            .collect();
                        out.push(line.join(" | "));
                    }
                }
            }
        }
        "divider" => out.push("─".repeat(width.min(40))),
        "button" => {
            let txt = format_terminal_text(obj.get("text"), resolve_sealed);
            out.push(ansi_wrap(ansi, tone, &format!("[ {txt} ]")));
        }
        _ => {}
    }
}

fn render_markdown_node(
    node: &Value,
    resolve_sealed: &impl Fn(&str) -> Option<String>,
    out: &mut Vec<String>,
) {
    let Some(obj) = node.as_object() else { return };
    let kind = obj.get("type").and_then(Value::as_str).unwrap_or("");
    match kind {
        "column" | "card" | "row" => {
            if let Some(children) = obj.get("children").and_then(Value::as_array) {
                for c in children {
                    render_markdown_node(c, resolve_sealed, out);
                }
            }
        }
        "heading" => {
            let txt = format_terminal_text(obj.get("text"), resolve_sealed);
            out.push(format!("### {txt}"));
        }
        "text" => out.push(format_terminal_text(obj.get("text"), resolve_sealed)),
        "badge" => {
            let txt = format_terminal_text(obj.get("text"), resolve_sealed);
            out.push(format!("`{txt}`"));
        }
        "stat" => {
            let label = format_terminal_text(obj.get("label"), resolve_sealed);
            let value = format_terminal_text(obj.get("value"), resolve_sealed);
            out.push(format!("- **{label}**: {value}"));
        }
        "bar" | "progress" => {
            let label = format_terminal_text(obj.get("label"), resolve_sealed);
            let caption = format_terminal_text(obj.get("caption"), resolve_sealed);
            if caption.is_empty() {
                let val = obj.get("value").and_then(Value::as_f64).unwrap_or(0.0);
                let max = obj.get("max").and_then(Value::as_f64).filter(|m| *m > 0.0).unwrap_or(1.0);
                out.push(format!("- **{label}**: {}%", ((val / max) * 100.0).round()));
            } else {
                out.push(format!("- **{label}**: {caption}"));
            }
        }
        "sparkline" => {
            if let Some(vals) = obj.get("values").and_then(Value::as_array) {
                out.push(format!("`{}`", render_sparkline(vals)));
            }
        }
        "table" => {
            if let Some(headers) = obj.get("headers").and_then(Value::as_array) {
                let hdrs: Vec<String> = headers
                    .iter()
                    .map(|h| format_terminal_text(Some(h), resolve_sealed))
                    .collect();
                out.push(format!("| {} |", hdrs.join(" | ")));
                out.push(format!("| {} |", vec!["---"; hdrs.len()].join(" | ")));
            }
            if let Some(rows) = obj.get("rows").and_then(Value::as_array) {
                for r in rows {
                    if let Some(cells) = r.as_array() {
                        let line: Vec<String> = cells
                            .iter()
                            .map(|c| format_terminal_text(Some(c), resolve_sealed))
                            .collect();
                        out.push(format!("| {} |", line.join(" | ")));
                    }
                }
            }
        }
        "divider" => out.push("---".into()),
        "button" => {
            let txt = format_terminal_text(obj.get("text"), resolve_sealed);
            out.push(format!("[{txt}]"));
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execute;

    #[test]
    fn wasm_vibe_alloc_and_vibe_invoke_exports_execute_cleanly() {
        let wat = r#"(module
            (memory (export "memory") 1)
            (data (i32.const 64) "{\"ok\":true,\"abi\":\"vibe\"}")
            (func (export "vibe_alloc") (param i32) (result i32) i32.const 1024)
            (func (export "vibe_invoke") (param i32 i32) (result i64)
                i64.const 103079215168))"#;
        // 24 << 32 | 64 = 103079215168
        let res = execute(wat.as_bytes(), br#"{"ping":1}"#).unwrap();
        assert_eq!(res["ok"], true);
        assert_eq!(res["abi"], "vibe");
    }

    #[test]
    fn adapts_a2ui_surface_with_sealed_handles_and_adaptive_cards() {
        let a2ui = json!({
            "surfaceUpdate": {
                "root": "root",
                "components": [
                    { "id": "root", "component": { "Column": { "children": { "explicitList": ["h", "b"] } } } },
                    { "id": "h", "component": { "Heading": { "text": { "literalString": "Servers" } } } },
                    { "id": "b", "component": { "Bar": { "label": { "sealed": "h_abc123" }, "value": 0.91, "caption": "91%", "tone": "danger" } } }
                ]
            }
        });
        let adapted = adapt_external_ui(&a2ui).unwrap();
        assert_eq!(adapted["type"], "column");
        assert_eq!(adapted["children"][0]["type"], "heading");
        assert_eq!(adapted["children"][1]["label"]["sealed"], "h_abc123");

        let card = json!({
            "type": "AdaptiveCard",
            "body": [
                { "type": "TextBlock", "text": "Host Alert", "style": "heading" },
                { "type": "FactSet", "facts": [{ "title": "CPU", "value": "94%" }] }
            ],
            "actions": [
                { "type": "Action.Submit", "title": "Ack", "verb": "ack" },
                { "type": "Action.OpenUrl", "title": "Bad", "url": "javascript:alert(1)" }
            ]
        });
        let adapted_card = adapt_external_ui(&card).unwrap();
        assert_eq!(adapted_card["children"][0]["type"], "heading");
        assert_eq!(adapted_card["children"][1]["type"], "table");
        assert_eq!(adapted_card["children"][2]["children"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn resolve_view_tree_and_terminal_markdown_hide_forged_sealed_handles() {
        let view = json!({
            "type": "column",
            "children": [
                { "type": "heading", "text": "Disk usage" },
                { "type": "bar", "label": { "sealed": "h_valid" }, "value": 0.85, "caption": "85%", "tone": "danger" },
                { "type": "bar", "label": { "sealed": "h_forged" }, "value": 0.25, "caption": "25%", "tone": "ok" },
                { "type": "sparkline", "values": [0.2, 0.5, 0.9], "tone": "warn" }
            ]
        });
        let resolver = |id: &str| -> Option<String> {
            (id == "h_valid").then(|| "db-1.prod.internal".to_owned())
        };

        let resolved = resolve_view_tree(&view, resolver).unwrap();
        assert_eq!(resolved["children"][1]["label"], "db-1.prod.internal");
        assert_eq!(resolved["children"][1]["sealed_resolved"], true);
        assert_eq!(resolved["children"][2]["label"], "");
        assert_eq!(resolved["children"][2]["sealed_resolved"], false);
        assert!(!resolved.to_string().contains("h_forged"));

        let term = render_terminal(&view, resolver, false, 60).unwrap();
        assert!(term.contains("🔒 db-1.prod.internal"));
        assert!(term.contains('█'));
        assert!(term.contains('▁'));
        assert!(!term.contains("h_forged"));
        assert!(!term.contains("h_valid"));

        let md = render_markdown(&view, resolver).unwrap();
        assert!(md.contains("### Disk usage"));
        assert!(md.contains("🔒 db-1.prod.internal"));
        assert!(!md.contains("h_forged"));
    }

    #[test]
    fn locale_strings_cover_cjk_and_arabic_rtl() {
        let zh = locale_strings("zh-CN");
        assert_eq!(zh.locale, "zh");
        assert!(!zh.is_rtl);
        assert!(!zh.allow_and_add.is_empty());

        let ar = locale_strings("ar");
        assert_eq!(ar.locale, "ar");
        assert!(ar.is_rtl);
        assert_eq!(ar.vibe_space, "مساحة Vibe");

        for code in ["en", "zh", "ja", "ko", "es", "fr", "de", "ar"] {
            let s = locale_strings(code);
            assert_eq!(s.locale, code);
            assert!(!s.sealed_legend.is_empty());
        }
    }
}
