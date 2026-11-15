//! Bidirectional UI compatibility adapters, handle-resolved native IR,
//! terminal/Markdown renderers, and multi-language locale strings.

use std::borrow::Cow;
use std::collections::{BTreeMap, HashSet};
use std::fmt::Write as _;
use std::io;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

use crate::{Error, MAX_MESSAGE_BYTES};

const MAX_DEPTH: usize = 16;
const MAX_NODES: usize = 1024;
const MAX_CANVAS_COMMANDS: usize = 2000;
const SPARK_BLOCKS: &[char] = &['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
const FORBIDDEN_PROTO_KEYS: &[&str] = &["__proto__", "constructor", "prototype"];
const FORBIDDEN_HANDLER_NAMES: &[&str] = &[
    "__proto__",
    "constructor",
    "prototype",
    "toString",
    "toLocaleString",
    "valueOf",
    "hasOwnProperty",
    "isPrototypeOf",
    "propertyIsEnumerable",
    "__defineGetter__",
    "__defineSetter__",
    "__lookupGetter__",
    "__lookupSetter__",
];

struct CountingWriter(usize);

impl io::Write for CountingWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0 = self.0.saturating_add(buf.len());
        if self.0 > MAX_MESSAGE_BYTES {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "message exceeds limit",
            ));
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

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
    let base = locale.trim().split(['-', '_']).next().unwrap_or("en");

    if base.eq_ignore_ascii_case("zh") {
        LocaleStrings {
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
        }
    } else if base.eq_ignore_ascii_case("ja") {
        LocaleStrings {
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
            sealed_legend: "鍵付きの値はシール済みで、ホストが描画し Vibe からは見えません。"
                .into(),
        }
    } else if base.eq_ignore_ascii_case("ko") {
        LocaleStrings {
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
            sealed_legend: "자물쇠가 있는 값은 봉인되어 호스트가 그리며 Vibe는 볼 수 없습니다."
                .into(),
        }
    } else if base.eq_ignore_ascii_case("es") {
        LocaleStrings {
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
            sealed_legend:
                "Los valores con candado están sellados. El anfitrión los dibuja; el vibe nunca los ve."
                    .into(),
        }
    } else if base.eq_ignore_ascii_case("fr") {
        LocaleStrings {
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
            sealed_legend:
                "Les valeurs avec cadenas sont scellées. L’hôte les affiche ; le vibe ne les voit jamais."
                    .into(),
        }
    } else if base.eq_ignore_ascii_case("de") {
        LocaleStrings {
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
            sealed_legend:
                "Werte mit Schloss sind versiegelt. Der Host zeichnet sie; das Vibe sieht sie nie."
                    .into(),
        }
    } else if base.eq_ignore_ascii_case("ar") {
        LocaleStrings {
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
        }
    } else {
        LocaleStrings {
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
            sealed_legend:
                "Values with a lock are sealed. The host draws them. The vibe never sees them."
                    .into(),
        }
    }
}

fn reject_prototype_keys(val: &Value, depth: usize) -> Result<(), Error> {
    if depth > 32 {
        return Err(Error::Package);
    }
    match val {
        Value::Object(map) => {
            for (k, v) in map {
                if FORBIDDEN_PROTO_KEYS.contains(&k.as_str()) {
                    return Err(Error::Package);
                }
                reject_prototype_keys(v, depth + 1)?;
            }
        }
        Value::Array(arr) => {
            for item in arr {
                reject_prototype_keys(item, depth + 1)?;
            }
        }
        _ => {}
    }
    Ok(())
}

/// Converts canonical VibeView, A2UI (`surfaceUpdate`/`components`), Adaptive Cards,
/// or Markdown into a validated canonical `VibeView` JSON object.
pub fn adapt_external_ui(raw: &Value) -> Result<Value, Error> {
    let mut counter = CountingWriter(0);
    serde_json::to_writer(&mut counter, raw).map_err(|_| Error::Package)?;
    reject_prototype_keys(raw, 0)?;

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
    let mut canvas_budget = MAX_CANVAS_COMMANDS;
    validate_canonical_node(&adapted, 0, &mut budget, &mut canvas_budget)?;
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
    let mut lines = Vec::with_capacity(16);
    render_terminal_node(
        &normalized,
        &resolve_sealed,
        ansi,
        clamped_width,
        &mut lines,
    );
    Ok(lines.join("\n"))
}

/// Renders a canonical or external UI view to Markdown.
pub fn render_markdown(
    view: &Value,
    resolve_sealed: impl Fn(&str) -> Option<String>,
) -> Result<String, Error> {
    let normalized = adapt_external_ui(view)?;
    let mut lines = Vec::with_capacity(16);
    render_markdown_node(&normalized, &resolve_sealed, &mut lines);
    Ok(lines.join("\n"))
}

fn find_ascii_icase(haystack: &[u8], needle_lower: &[u8], from: usize) -> Option<usize> {
    if needle_lower.is_empty() || haystack.len() < from + needle_lower.len() {
        return None;
    }
    let first = needle_lower[0];
    let end = haystack.len() - needle_lower.len();
    let mut i = from;
    while i <= end {
        if haystack[i].to_ascii_lowercase() == first
            && haystack[i..i + needle_lower.len()].eq_ignore_ascii_case(needle_lower)
        {
            return Some(i);
        }
        i += 1;
    }
    None
}

fn sanitize_plain_text(s: &str) -> Cow<'_, str> {
    let bytes = s.as_bytes();
    let has_nul = bytes.contains(&0);
    let has_script = find_ascii_icase(bytes, b"<script", 0).is_some();
    let has_js = find_ascii_icase(bytes, b"javascript:", 0).is_some();
    if !has_nul && !has_script && !has_js {
        return Cow::Borrowed(s);
    }

    let mut out = String::with_capacity(s.len());
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == 0 {
            i += 1;
            continue;
        }
        if bytes.len() - i >= 7 && bytes[i..i + 7].eq_ignore_ascii_case(b"<script") {
            if let Some(end_tag) = find_ascii_icase(bytes, b"</script>", i + 7) {
                i = end_tag + 9;
                continue;
            }
            break;
        }
        if bytes.len() - i >= 11 && bytes[i..i + 11].eq_ignore_ascii_case(b"javascript:") {
            i += 11;
            continue;
        }
        if let Some(ch) = s[i..].chars().next() {
            out.push(ch);
            i += ch.len_utf8();
        } else {
            break;
        }
    }
    Cow::Owned(out)
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
        Some(Value::String(s)) => Value::String(sanitize_plain_text(s).into_owned()),
        Some(Value::Number(n)) => Value::String(n.to_string()),
        Some(Value::Bool(b)) => Value::String(b.to_string()),
        Some(Value::Object(obj)) => {
            if let Some(lit) = obj.get("literalString") {
                normalize_text_value(Some(lit))
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
    let Some(s) = val else {
        return "default";
    };
    if s.eq_ignore_ascii_case("ok")
        || s.eq_ignore_ascii_case("good")
        || s.eq_ignore_ascii_case("success")
        || s.eq_ignore_ascii_case("positive")
    {
        "ok"
    } else if s.eq_ignore_ascii_case("warn")
        || s.eq_ignore_ascii_case("warning")
        || s.eq_ignore_ascii_case("caution")
    {
        "warn"
    } else if s.eq_ignore_ascii_case("danger")
        || s.eq_ignore_ascii_case("error")
        || s.eq_ignore_ascii_case("attention")
        || s.eq_ignore_ascii_case("critical")
    {
        "danger"
    } else {
        "default"
    }
}

fn starts_with_ignore_ascii_case(s: &str, prefix: &str) -> bool {
    s.get(..prefix.len())
        .is_some_and(|head| head.eq_ignore_ascii_case(prefix))
}

fn is_safe_action_url(url: &str) -> bool {
    let trimmed = url.trim();
    !starts_with_ignore_ascii_case(trimmed, "javascript:")
        && !starts_with_ignore_ascii_case(trimmed, "vbscript:")
        && !starts_with_ignore_ascii_case(trimmed, "data:")
}

fn is_valid_handler_name(raw: &str) -> bool {
    let bytes = raw.as_bytes();
    if bytes.is_empty() || bytes.len() > 64 {
        return false;
    }
    let first = bytes[0];
    if !(first.is_ascii_alphabetic() || first == b'_' || first == b'$') {
        return false;
    }
    if !bytes[1..]
        .iter()
        .all(|&b| b.is_ascii_alphanumeric() || b == b'_' || b == b'$')
    {
        return false;
    }
    !FORBIDDEN_HANDLER_NAMES.contains(&raw)
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

    let mut by_id: BTreeMap<&str, &Value> = BTreeMap::new();
    let mut first_id: Option<&str> = None;
    for entry in comps {
        if let Some(obj) = entry.as_object()
            && let Some(id) = obj.get("id").and_then(Value::as_str)
        {
            if first_id.is_none() {
                first_id = Some(id);
            }
            by_id.insert(id, entry);
        }
    }

    if let Some(root_id) = surface
        .get("root")
        .and_then(Value::as_str)
        .or_else(|| by_id.contains_key("root").then_some("root"))
        .or(first_id)
        && let Some(root_val) = by_id.get(root_id)
    {
        let mut visiting = HashSet::with_capacity(8);
        return adapt_a2ui_node(root_val, &by_id, &mut visiting, 0);
    }

    let mut children = Vec::with_capacity(comps.len());
    let mut visiting = HashSet::with_capacity(8);
    for entry in comps {
        visiting.clear();
        children.push(adapt_a2ui_node(entry, &by_id, &mut visiting, 1)?);
    }
    Ok(json!({ "type": "column", "children": children }))
}

fn adapt_a2ui_node<'a>(
    raw: &'a Value,
    by_id: &BTreeMap<&'a str, &'a Value>,
    visiting: &mut HashSet<&'a str>,
    depth: usize,
) -> Result<Value, Error> {
    if depth > MAX_DEPTH {
        return Err(Error::Package);
    }
    if let Some(ref_id) = raw.as_str() {
        if !visiting.insert(ref_id) {
            return Err(Error::Package);
        }
        let target = by_id.get(ref_id).ok_or(Error::Package)?;
        let res = adapt_a2ui_node(target, by_id, visiting, depth);
        visiting.remove(ref_id);
        return res;
    }

    let obj = raw.as_object().ok_or(Error::Package)?;
    let comp = obj
        .get("component")
        .and_then(Value::as_object)
        .unwrap_or(obj);

    let (kind, props): (&str, &Map<String, Value>) =
        if let Some(t) = comp.get("type").and_then(Value::as_str) {
            (t, comp)
        } else if let Some((k, v)) = comp.iter().find(|(k, v)| {
            v.is_object() && k.chars().next().is_some_and(|c| c.is_ascii_uppercase())
        }) {
            (k.as_str(), v.as_object().ok_or(Error::Package)?)
        } else {
            return normalize_canonical_node(raw, depth);
        };

    let tone = normalize_tone(props.get("tone").and_then(Value::as_str));

    match kind {
        "Column" | "Row" | "Card" => {
            let out_type = match kind {
                "Column" => "column",
                "Row" => "row",
                _ => "card",
            };
            let raw_children = props
                .get("children")
                .and_then(|c| {
                    c.as_array()
                        .or_else(|| c.get("explicitList").and_then(Value::as_array))
                })
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let mut out_children = Vec::with_capacity(raw_children.len());
            for child in raw_children {
                out_children.push(adapt_a2ui_node(child, by_id, visiting, depth + 1)?);
            }
            if out_children.is_empty()
                && let Some(child_ref) = props.get("child")
            {
                out_children.push(adapt_a2ui_node(child_ref, by_id, visiting, depth + 1)?);
            }
            Ok(json!({ "type": out_type, "children": out_children }))
        }
        "Heading" => Ok(json!({
            "type": "heading",
            "text": normalize_text_value(props.get("text").or_else(|| props.get("title")))
        })),
        "Text" => {
            let hint = props.get("usageHint").and_then(Value::as_str).unwrap_or("");
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
            let raw_opts = props
                .get("options")
                .or_else(|| props.get("selections"))
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let opts = sanitize_option_items(raw_opts);
            Ok(json!({
                "type": "option_group",
                "id": sanitize_plain_text(props.get("id").and_then(Value::as_str).unwrap_or("choice")),
                "label": normalize_text_value(props.get("label")),
                "options": opts
            }))
        }
        "Table" => {
            let headers = props
                .get("headers")
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let rows = props
                .get("rows")
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            Ok(json!({
                "type": "table",
                "headers": sanitize_table_headers(headers),
                "rows": sanitize_table_rows(rows)
            }))
        }
        "Divider" => Ok(json!({ "type": "divider" })),
        _ => Err(Error::Package),
    }
}

fn adapt_adaptive_card(card: &Map<String, Value>) -> Result<Value, Error> {
    let body = card
        .get("body")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or(&[]);
    let actions = card
        .get("actions")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or(&[]);
    let mut children = Vec::with_capacity(body.len() + usize::from(!actions.is_empty()));
    for item in body {
        children.push(adapt_adaptive_element(item, 1)?);
    }
    if !actions.is_empty() {
        let mut action_row = Vec::with_capacity(actions.len());
        for act in actions {
            if let Some(btn) = adapt_adaptive_action(act) {
                action_row.push(btn);
            }
        }
        if !action_row.is_empty() {
            children.push(json!({ "type": "row", "children": action_row }));
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
        .unwrap_or(if act_type.is_empty() {
            "submit"
        } else {
            act_type
        });
    let mut node = json!({
        "type": "button",
        "text": title,
        "command": sanitize_plain_text(cmd),
        "tone": normalize_tone(obj.get("style").and_then(Value::as_str))
    });
    if let Some(data) = obj.get("data")
        && data.is_object()
    {
        node.as_object_mut()
            .expect("object")
            .insert("args".into(), data.clone());
    }
    Some(node)
}

fn adapt_adaptive_element(elem: &Value, depth: usize) -> Result<Value, Error> {
    if depth > MAX_DEPTH {
        return Err(Error::Package);
    }
    let obj = elem.as_object().ok_or(Error::Package)?;
    let kind = obj
        .get("type")
        .and_then(Value::as_str)
        .ok_or(Error::Package)?;
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
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let mut children = Vec::with_capacity(items.len());
            for item in items {
                children.push(adapt_adaptive_element(item, depth + 1)?);
            }
            Ok(json!({ "type": "card", "children": children }))
        }
        "ColumnSet" => {
            let cols = obj
                .get("columns")
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let mut children = Vec::with_capacity(cols.len());
            for col in cols {
                children.push(adapt_adaptive_element(col, depth + 1)?);
            }
            Ok(json!({ "type": "row", "children": children }))
        }
        "Column" => {
            let items = obj
                .get("items")
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let mut children = Vec::with_capacity(items.len());
            for item in items {
                children.push(adapt_adaptive_element(item, depth + 1)?);
            }
            Ok(json!({ "type": "column", "children": children }))
        }
        "FactSet" => {
            let facts = obj
                .get("facts")
                .and_then(Value::as_array)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
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
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let mut opts = Vec::with_capacity(choices.len());
            for c in choices {
                if let Some(co) = c.as_object() {
                    opts.push(json!({
                        "label": normalize_text_value(co.get("title")),
                        "value": normalize_text_value(co.get("value"))
                    }));
                }
            }
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
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let mut btns = Vec::with_capacity(actions.len());
            for act in actions {
                if let Some(btn) = adapt_adaptive_action(act) {
                    btns.push(btn);
                }
            }
            Ok(json!({ "type": "row", "children": btns }))
        }
        _ => Err(Error::Package),
    }
}

fn adapt_markdown(markdown: &str) -> Value {
    let cleaned = sanitize_plain_text(markdown);
    let lines: Vec<&str> = cleaned.lines().collect();
    let mut children = Vec::with_capacity(lines.len().min(MAX_NODES));
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
                let mut row = Vec::with_capacity(headers.len());
                for c in lines[i].trim().trim_matches('|').split('|') {
                    row.push(json!(c.trim()));
                }
                rows.push(Value::Array(row));
                i += 1;
            }
            children.push(json!({ "type": "table", "headers": headers, "rows": rows }));
            continue;
        }
        let text = line
            .strip_prefix("- ")
            .or_else(|| line.strip_prefix("* "))
            .unwrap_or(line);
        children.push(json!({ "type": "text", "text": text }));
        i += 1;
    }
    json!({ "type": "column", "children": children })
}

fn sanitize_table_headers(headers: &[Value]) -> Vec<Value> {
    let mut out = Vec::with_capacity(headers.len().min(32));
    for h in headers.iter().take(32) {
        out.push(normalize_text_value(Some(h)));
    }
    out
}

fn sanitize_table_rows(rows: &[Value]) -> Vec<Value> {
    let mut out = Vec::with_capacity(rows.len().min(200));
    for row in rows.iter().take(200) {
        if let Some(cells) = row.as_array() {
            let mut clean_row = Vec::with_capacity(cells.len().min(32));
            for c in cells.iter().take(32) {
                clean_row.push(normalize_text_value(Some(c)));
            }
            out.push(Value::Array(clean_row));
        }
    }
    out
}

fn sanitize_option_items(options: &[Value]) -> Vec<Value> {
    let mut out = Vec::with_capacity(options.len().min(50));
    for (idx, opt) in options.iter().take(50).enumerate() {
        let Some(obj) = opt.as_object() else {
            continue;
        };
        let mut clean = obj.clone();
        if let Some(lbl) = obj.get("label") {
            clean.insert("label".into(), normalize_text_value(Some(lbl)));
        } else {
            clean.insert("label".into(), Value::String(format!("Option {}", idx + 1)));
        }
        if let Some(id_val) = obj.get("id").and_then(Value::as_str) {
            clean.insert(
                "id".into(),
                Value::String(sanitize_plain_text(id_val).into_owned()),
            );
        }
        out.push(Value::Object(clean));
    }
    out
}

fn clamp_canvas_dim(val: Option<&Value>, default_val: u64) -> Value {
    match val {
        Some(v) if v.is_u64() => {
            let u = v.as_u64().expect("checked u64");
            json!(u.clamp(16, 2048))
        }
        Some(v) if v.as_f64().is_some_and(f64::is_finite) => {
            let f = v.as_f64().expect("checked f64");
            json!(f.clamp(16.0, 2048.0))
        }
        _ => json!(default_val),
    }
}

fn sanitize_canvas_commands(cmds: &[Value]) -> Result<Vec<Value>, Error> {
    let mut out = Vec::with_capacity(cmds.len());
    for cmd in cmds {
        let cmd_obj = cmd.as_object().ok_or(Error::Package)?;
        let mut clean = Map::new();
        for (k, v) in cmd_obj {
            if k == "text" {
                clean.insert("text".into(), normalize_text_value(Some(v)));
            } else {
                clean.insert(k.clone(), v.clone());
            }
        }
        out.push(Value::Object(clean));
    }
    Ok(out)
}

fn normalize_style_tokens(raw_style: &Value) -> Option<Value> {
    const ALLOWED_FONT_WEIGHTS: &[&str] = &[
        "normal", "medium", "semibold", "bold", "100", "200", "300", "400", "500", "600", "700",
        "800", "900",
    ];
    const ALLOWED_ALIGNS: &[&str] = &[
        "start",
        "center",
        "end",
        "stretch",
        "left",
        "right",
        "baseline",
        "space-between",
        "spaceBetween",
        "space_between",
        "space-around",
        "spaceAround",
        "space-evenly",
        "spaceEvenly",
    ];
    let obj = raw_style.as_object()?;
    let mut out = Map::new();
    for k in [
        "padding",
        "paddingHorizontal",
        "paddingVertical",
        "margin",
        "gap",
        "radius",
        "borderRadius",
        "borderWidth",
        "fontSize",
        "width",
        "height",
        "minWidth",
        "maxWidth",
        "minHeight",
        "maxHeight",
        "elevation",
    ] {
        if let Some(v) = obj.get(k) {
            if let Some(u) = v.as_u64() {
                out.insert(k.to_owned(), json!(u.min(2048)));
            } else if let Some(n) = v.as_f64()
                && n.is_finite()
            {
                out.insert(k.to_owned(), json!(n.clamp(0.0, 2048.0)));
            }
        }
    }
    if let Some(flex) = obj.get("flex").and_then(Value::as_f64)
        && flex.is_finite()
        && flex > 0.0
    {
        out.insert("flex".into(), json!(flex.clamp(0.0, 24.0).round()));
    }
    if let Some(opacity) = obj.get("opacity").and_then(Value::as_f64)
        && opacity.is_finite()
    {
        out.insert("opacity".into(), json!(opacity.clamp(0.0, 1.0)));
    }
    for ck in ["bg", "fg", "backgroundColor", "borderColor", "color"] {
        if let Some(cs) = obj.get(ck).and_then(Value::as_str)
            && is_safe_canvas_color(cs)
        {
            out.insert(ck.to_owned(), Value::String(cs.trim().to_owned()));
        }
    }
    if let Some(fw_val) = obj.get("fontWeight") {
        if let Some(fw_num) = fw_val.as_u64() {
            if (100..=900).contains(&fw_num) && fw_num.is_multiple_of(100) {
                out.insert("fontWeight".into(), Value::String(fw_num.to_string()));
            }
        } else if let Some(s) = fw_val.as_str() {
            let trimmed = s.trim();
            if let Some(matched) = ALLOWED_FONT_WEIGHTS
                .iter()
                .find(|allowed| trimmed.eq_ignore_ascii_case(allowed))
            {
                out.insert("fontWeight".into(), Value::String((*matched).to_owned()));
            }
        }
    }
    for ak in ["align", "justify", "crossAlign"] {
        if let Some(s) = obj.get(ak).and_then(Value::as_str) {
            let trimmed = s.trim();
            if ALLOWED_ALIGNS.contains(&trimmed) {
                out.insert(ak.to_owned(), Value::String(trimmed.to_owned()));
            }
        }
    }
    (!out.is_empty()).then_some(Value::Object(out))
}

fn normalize_canonical_node(raw: &Value, depth: usize) -> Result<Value, Error> {
    if depth > MAX_DEPTH {
        return Err(Error::Package);
    }
    let obj = raw.as_object().ok_or(Error::Package)?;
    let kind = obj
        .get("type")
        .and_then(Value::as_str)
        .ok_or(Error::Package)?;
    let mut out = Map::new();

    for (k, v) in obj {
        match k.as_str() {
            "type" => {
                let mapped = if kind == "action" { "button" } else { kind };
                out.insert("type".into(), Value::String(mapped.to_owned()));
            }
            "tone" => {
                out.insert(
                    "tone".into(),
                    Value::String(normalize_tone(v.as_str()).to_owned()),
                );
            }
            "text" | "label" | "caption" | "title" => {
                out.insert(k.clone(), normalize_text_value(Some(v)));
            }
            "value" => {
                if (v.is_number() && (kind == "bar" || kind == "progress"))
                    || (v.is_boolean() && kind == "checkbox")
                {
                    out.insert(k.clone(), v.clone());
                } else {
                    out.insert(k.clone(), normalize_text_value(Some(v)));
                }
            }
            "headers" if kind == "table" => {
                let headers = v.as_array().ok_or(Error::Package)?;
                out.insert(
                    "headers".into(),
                    Value::Array(sanitize_table_headers(headers)),
                );
            }
            "rows" if kind == "table" => {
                let rows = v.as_array().ok_or(Error::Package)?;
                out.insert("rows".into(), Value::Array(sanitize_table_rows(rows)));
            }
            "commands" if kind == "canvas" => {
                let cmds = v.as_array().ok_or(Error::Package)?;
                out.insert(
                    "commands".into(),
                    Value::Array(sanitize_canvas_commands(cmds)?),
                );
            }
            "width" if kind == "canvas" => {
                out.insert("width".into(), clamp_canvas_dim(Some(v), 260));
            }
            "height" if kind == "canvas" => {
                out.insert("height".into(), clamp_canvas_dim(Some(v), 56));
            }
            "options" if kind == "option_group" => {
                let opts = v.as_array().ok_or(Error::Package)?;
                out.insert("options".into(), Value::Array(sanitize_option_items(opts)));
            }
            "bindtap" | "bindinput" | "bindchange" => {
                if !v.is_null() {
                    let s = v.as_str().ok_or(Error::Package)?.trim();
                    if !is_valid_handler_name(s) {
                        return Err(Error::Package);
                    }
                    out.insert(k.clone(), Value::String(s.to_owned()));
                }
            }
            "command" => {
                if !v.is_null() {
                    let s = v.as_str().ok_or(Error::Package)?.trim();
                    if FORBIDDEN_HANDLER_NAMES.contains(&s) {
                        return Err(Error::Package);
                    }
                    out.insert(
                        k.clone(),
                        Value::String(sanitize_plain_text(s).into_owned()),
                    );
                }
            }
            "id" => {
                if !v.is_null() {
                    let s = v.as_str().ok_or(Error::Package)?.trim();
                    if FORBIDDEN_PROTO_KEYS.contains(&s) {
                        return Err(Error::Package);
                    }
                    out.insert(
                        k.clone(),
                        Value::String(sanitize_plain_text(s).into_owned()),
                    );
                }
            }
            "style" => {
                if !v.is_null()
                    && let Some(clean_style) = normalize_style_tokens(v)
                {
                    out.insert(k.clone(), clean_style);
                }
            }
            "children" => {
                let children = v.as_array().ok_or(Error::Package)?;
                let mut next = Vec::with_capacity(children.len());
                for c in children {
                    next.push(normalize_canonical_node(c, depth + 1)?);
                }
                out.insert("children".into(), Value::Array(next));
            }
            _ => {
                out.insert(k.clone(), v.clone());
            }
        }
    }

    if kind == "canvas" {
        out.entry("width").or_insert_with(|| json!(260));
        out.entry("height").or_insert_with(|| json!(56));
    }

    Ok(Value::Object(out))
}

fn validate_gradient_colors(grad: &Value) -> Result<(), Error> {
    if grad.is_null() {
        return Ok(());
    }
    let gobj = grad.as_object().ok_or(Error::Package)?;
    let colors = gobj
        .get("colors")
        .and_then(Value::as_array)
        .ok_or(Error::Package)?;
    for c in colors {
        let cs = c.as_str().ok_or(Error::Package)?;
        if !is_safe_canvas_color(cs) {
            return Err(Error::Package);
        }
    }
    Ok(())
}

fn validate_canonical_node(
    node: &Value,
    depth: usize,
    budget: &mut usize,
    canvas_budget: &mut usize,
) -> Result<(), Error> {
    if depth > MAX_DEPTH || *budget == 0 {
        return Err(Error::Package);
    }
    *budget -= 1;
    let obj = node.as_object().ok_or(Error::Package)?;
    let kind = obj
        .get("type")
        .and_then(Value::as_str)
        .ok_or(Error::Package)?;
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
        "canvas",
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

    for key in ["bindtap", "bindinput", "bindchange"] {
        if let Some(hv) = obj.get(key)
            && !hv.is_null()
        {
            let hs = hv.as_str().ok_or(Error::Package)?;
            if !is_valid_handler_name(hs) {
                return Err(Error::Package);
            }
        }
    }
    if let Some(cmd) = obj.get("command")
        && !cmd.is_null()
    {
        let cs = cmd.as_str().ok_or(Error::Package)?;
        if FORBIDDEN_HANDLER_NAMES.contains(&cs) {
            return Err(Error::Package);
        }
    }
    if kind == "bar"
        && let Some(swatch) = obj.get("swatch")
        && !swatch.is_null()
    {
        let ss = swatch.as_str().ok_or(Error::Package)?;
        if !is_safe_canvas_color(ss) {
            return Err(Error::Package);
        }
    }

    if kind == "canvas" {
        const VALID_OPS: &[&str] = &[
            "clear", "rect", "rrect", "circle", "arc", "line", "path", "polygon", "bars", "text",
        ];
        let cmds = obj
            .get("commands")
            .and_then(Value::as_array)
            .ok_or(Error::Package)?;
        if cmds.len() > *canvas_budget {
            return Err(Error::Package);
        }
        *canvas_budget -= cmds.len();
        for cmd in cmds {
            let cmd_obj = cmd.as_object().ok_or(Error::Package)?;
            let op = cmd_obj
                .get("op")
                .or_else(|| cmd_obj.get("type"))
                .and_then(Value::as_str)
                .ok_or(Error::Package)?;
            if !VALID_OPS.contains(&op) {
                return Err(Error::Package);
            }
            for color_key in ["fill", "stroke", "color", "swatch"] {
                if let Some(cv) = cmd_obj.get(color_key)
                    && !cv.is_null()
                {
                    let cs = cv.as_str().ok_or(Error::Package)?;
                    if !is_safe_canvas_color(cs) {
                        return Err(Error::Package);
                    }
                }
            }
            if let Some(grad) = cmd_obj.get("linearGradient") {
                validate_gradient_colors(grad)?;
            }
            if let Some(grad) = cmd_obj.get("radialGradient") {
                validate_gradient_colors(grad)?;
            }
            if let Some(d_val) = cmd_obj.get("d")
                && !d_val.is_null()
            {
                let d_str = d_val.as_str().ok_or(Error::Package)?;
                if !is_safe_svg_path(d_str) {
                    return Err(Error::Package);
                }
            }
            if op == "polygon"
                && let Some(pts_val) = cmd_obj.get("points")
                && !pts_val.is_null()
            {
                let pts = pts_val.as_array().ok_or(Error::Package)?;
                if pts.len() > 512 {
                    return Err(Error::Package);
                }
            }
        }
    }
    if let Some(children) = obj.get("children") {
        let arr = children.as_array().ok_or(Error::Package)?;
        for child in arr {
            validate_canonical_node(child, depth + 1, budget, canvas_budget)?;
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
    let kind = obj.get("type").and_then(Value::as_str).unwrap_or("");
    let mut out = Map::new();
    let mut had_sealed = false;
    let mut all_resolved = true;

    for (k, v) in obj {
        match k.as_str() {
            "text" | "label" | "caption" | "title" => {
                let (resolved, is_sealed, ok) = resolve_text_value(Some(v), resolve_sealed);
                if is_sealed {
                    had_sealed = true;
                    all_resolved &= ok;
                }
                out.insert(k.clone(), Value::String(resolved));
            }
            "value" => {
                if (kind == "bar" || kind == "progress") && v.is_number()
                    || kind == "checkbox" && v.is_boolean()
                {
                    out.insert(k.clone(), v.clone());
                } else {
                    let (resolved, is_sealed, ok) = resolve_text_value(Some(v), resolve_sealed);
                    if is_sealed {
                        had_sealed = true;
                        all_resolved &= ok;
                    }
                    out.insert(k.clone(), Value::String(resolved));
                }
            }
            "headers" if v.is_array() => {
                let headers = v.as_array().expect("checked array");
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
            "rows" if v.is_array() => {
                let rows = v.as_array().expect("checked array");
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
            "commands" if kind == "canvas" && v.is_array() => {
                let cmds = v.as_array().expect("checked array");
                let mut resolved_cmds = Vec::with_capacity(cmds.len());
                for cmd in cmds {
                    let mut cmd_out = cmd.clone();
                    if let Some(cmd_obj) = cmd_out.as_object_mut()
                        && let Some(txt_val) = cmd_obj.get("text").cloned()
                    {
                        let (txt, is_sealed, ok) =
                            resolve_text_value(Some(&txt_val), resolve_sealed);
                        if is_sealed {
                            had_sealed = true;
                            all_resolved &= ok;
                        }
                        cmd_obj.insert("text".into(), Value::String(txt));
                    }
                    resolved_cmds.push(cmd_out);
                }
                out.insert("commands".into(), Value::Array(resolved_cmds));
            }
            "options" if kind == "option_group" && v.is_array() => {
                let opts = v.as_array().expect("checked array");
                let mut resolved_opts = Vec::with_capacity(opts.len());
                for opt in opts {
                    let mut opt_out = opt.clone();
                    if let Some(opt_obj) = opt_out.as_object_mut()
                        && let Some(lbl_val) = opt_obj.get("label").cloned()
                    {
                        let (txt, is_sealed, ok) =
                            resolve_text_value(Some(&lbl_val), resolve_sealed);
                        if is_sealed {
                            had_sealed = true;
                            all_resolved &= ok;
                        }
                        opt_obj.insert("label".into(), Value::String(txt));
                    }
                    resolved_opts.push(opt_out);
                }
                out.insert("options".into(), Value::Array(resolved_opts));
            }
            "children" if v.is_array() => {
                let children = v.as_array().expect("checked array");
                let mut next = Vec::with_capacity(children.len());
                for c in children {
                    next.push(resolve_node_recursive(c, resolve_sealed)?);
                }
                out.insert("children".into(), Value::Array(next));
            }
            _ => {
                out.insert(k.clone(), v.clone());
            }
        }
    }

    if had_sealed {
        out.insert("sealed".into(), Value::Bool(true));
        out.insert("sealed_resolved".into(), Value::Bool(all_resolved));
    }

    Ok(Value::Object(out))
}

fn is_safe_canvas_color(raw: &str) -> bool {
    let s = raw.trim();
    if s.is_empty() {
        return false;
    }
    if let Some(hex) = s.strip_prefix('#') {
        return matches!(hex.len(), 3 | 6 | 8) && hex.bytes().all(|b| b.is_ascii_hexdigit());
    }
    const PALETTE: &[&str] = &[
        "default",
        "accent",
        "ok",
        "warn",
        "danger",
        "surface",
        "card",
        "border",
        "text",
        "muted",
        "transparent",
        "none",
        "currentcolor",
    ];
    PALETTE.iter().any(|tok| s.eq_ignore_ascii_case(tok))
}

fn is_safe_svg_path(raw: &str) -> bool {
    let s = raw.trim();
    !s.is_empty()
        && s.len() <= 4096
        && s.bytes().all(|b| {
            b.is_ascii_digit()
                || b.is_ascii_whitespace()
                || matches!(
                    b,
                    b'M' | b'm'
                        | b'L'
                        | b'l'
                        | b'H'
                        | b'h'
                        | b'V'
                        | b'v'
                        | b'C'
                        | b'c'
                        | b'S'
                        | b's'
                        | b'Q'
                        | b'q'
                        | b'T'
                        | b't'
                        | b'A'
                        | b'a'
                        | b'Z'
                        | b'z'
                        | b'.'
                        | b','
                        | b'e'
                        | b'E'
                        | b'+'
                        | b'-'
                )
        })
}

fn skip_csi_sequence(bytes: &[u8], mut i: usize) -> usize {
    while i < bytes.len() && (0x30..=0x3F).contains(&bytes[i]) {
        i += 1;
    }
    while i < bytes.len() && (0x20..=0x2F).contains(&bytes[i]) {
        i += 1;
    }
    if i < bytes.len() && (0x40..=0x7E).contains(&bytes[i]) {
        i += 1;
    }
    i
}

fn skip_st_terminated_sequence(bytes: &[u8], mut i: usize) -> usize {
    while i < bytes.len() {
        if bytes[i] == 0x07 {
            return i + 1;
        }
        if bytes[i] == 0x1B && bytes.get(i + 1) == Some(&b'\\') {
            return i + 2;
        }
        if bytes[i] == 0xC2 && bytes.get(i + 1) == Some(&0x9C) {
            return i + 2;
        }
        i += 1;
    }
    bytes.len()
}

fn strip_terminal_controls(raw: &str) -> Cow<'_, str> {
    if raw
        .bytes()
        .all(|b| (0x20..=0x7E).contains(&b) || b == b'\t' || b == b'\n')
    {
        return Cow::Borrowed(raw);
    }

    let bytes = raw.as_bytes();
    let mut out = String::with_capacity(raw.len());
    let mut i = 0usize;
    while i < bytes.len() {
        let b = bytes[i];
        if b == 0x1B {
            match bytes.get(i + 1).copied() {
                Some(b'[') => {
                    i = skip_csi_sequence(bytes, i + 2);
                    continue;
                }
                Some(b']' | b'P' | b'X' | b'^' | b'_') => {
                    i = skip_st_terminated_sequence(bytes, i + 2);
                    continue;
                }
                Some(next) if (0x20..=0x7E).contains(&next) => {
                    i += 2;
                    continue;
                }
                _ => {
                    i += 1;
                    continue;
                }
            }
        }
        // UTF-8 C1 control block U+0080..=U+009F is encoded as [0xC2, 0x80..=0x9F].
        if b == 0xC2
            && let Some(&c1) = bytes.get(i + 1)
            && (0x80..=0x9F).contains(&c1)
        {
            match c1 {
                0x9B => {
                    i = skip_csi_sequence(bytes, i + 2);
                }
                0x9D | 0x90 | 0x98 | 0x9E | 0x9F => {
                    i = skip_st_terminated_sequence(bytes, i + 2);
                }
                _ => {
                    i += 2;
                }
            }
            continue;
        }
        if b <= 0x08 || (0x0B..=0x1F).contains(&b) || b == 0x7F {
            i += 1;
            continue;
        }
        if b < 0x80 {
            out.push(b as char);
            i += 1;
        } else if let Some(ch) = raw[i..].chars().next() {
            out.push(ch);
            i += ch.len_utf8();
        } else {
            break;
        }
    }
    Cow::Owned(out)
}

fn format_terminal_text(
    val: Option<&Value>,
    resolve_sealed: &impl Fn(&str) -> Option<String>,
) -> String {
    let (txt, is_sealed, ok) = resolve_text_value(val, resolve_sealed);
    let safe_txt = strip_terminal_controls(&txt);
    if is_sealed {
        if ok {
            format!("🔒 {safe_txt}")
        } else {
            String::new()
        }
    } else {
        safe_txt.into_owned()
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
    let mut nums = Vec::with_capacity(values.len());
    for v in values {
        if let Some(f) = v.as_f64()
            && f.is_finite()
        {
            nums.push(f);
        }
    }
    if nums.is_empty() {
        return String::new();
    }
    let min = nums.iter().copied().fold(f64::INFINITY, f64::min);
    let max = nums.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let span = max - min;
    let mut out = String::with_capacity(nums.len() * 3);
    for v in nums {
        let idx = if span <= f64::EPSILON {
            3
        } else {
            (((v - min) / span) * ((SPARK_BLOCKS.len() - 1) as f64)).round() as usize
        };
        out.push(SPARK_BLOCKS[idx.min(SPARK_BLOCKS.len() - 1)]);
    }
    out
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
            if let Some(children) = obj.get("children").and_then(Value::as_array) {
                let mut parts = Vec::with_capacity(children.len());
                let mut sub = Vec::with_capacity(4);
                for c in children {
                    sub.clear();
                    render_terminal_node(c, resolve_sealed, ansi, width, &mut sub);
                    if !sub.is_empty() {
                        parts.push(sub.join(" "));
                    }
                }
                if !parts.is_empty() {
                    out.push(parts.join(" | "));
                }
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
            let max = obj
                .get("max")
                .and_then(Value::as_f64)
                .filter(|m| *m > 0.0)
                .unwrap_or(1.0);
            let frac = (val / max).clamp(0.0, 1.0);
            let bar_w = (width / 3).clamp(10, 28);
            let filled = (frac * (bar_w as f64)).round() as usize;
            let mut bar = String::with_capacity(bar_w * 3);
            for _ in 0..filled {
                bar.push('█');
            }
            for _ in filled..bar_w {
                bar.push('░');
            }
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
        "canvas" => {
            if let Some(cmds) = obj.get("commands").and_then(Value::as_array) {
                let mut chunks = Vec::with_capacity(cmds.len().min(32));
                for cmd in cmds {
                    if let Some(co) = cmd.as_object() {
                        let op = co
                            .get("op")
                            .or_else(|| co.get("type"))
                            .and_then(Value::as_str)
                            .unwrap_or("");
                        if op == "bars" {
                            if let Some(vals) = co.get("values").and_then(Value::as_array) {
                                let spark = render_sparkline(vals);
                                if !spark.is_empty() {
                                    chunks.push(spark);
                                }
                            }
                        } else if op == "text" {
                            let txt = format_terminal_text(co.get("text"), resolve_sealed);
                            if !txt.is_empty() {
                                chunks.push(txt);
                            }
                        }
                    }
                }
                if !chunks.is_empty() {
                    out.push(ansi_wrap(ansi, tone, &chunks.join(" ")));
                } else {
                    let w = obj.get("width").and_then(Value::as_u64).unwrap_or(260);
                    let h = obj.get("height").and_then(Value::as_u64).unwrap_or(56);
                    out.push(format!("[canvas {w}x{h}]"));
                }
            }
        }
        "table" => {
            if let Some(headers) = obj.get("headers").and_then(Value::as_array) {
                let mut hdrs = Vec::with_capacity(headers.len());
                for h in headers {
                    hdrs.push(format_terminal_text(Some(h), resolve_sealed));
                }
                out.push(hdrs.join(" | "));
                out.push("-".repeat(width.min(48)));
            }
            if let Some(rows) = obj.get("rows").and_then(Value::as_array) {
                for r in rows {
                    if let Some(cells) = r.as_array() {
                        let mut line = Vec::with_capacity(cells.len());
                        for c in cells {
                            line.push(format_terminal_text(Some(c), resolve_sealed));
                        }
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
                let max = obj
                    .get("max")
                    .and_then(Value::as_f64)
                    .filter(|m| *m > 0.0)
                    .unwrap_or(1.0);
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
        "canvas" => {
            let w = obj.get("width").and_then(Value::as_u64).unwrap_or(260);
            let h = obj.get("height").and_then(Value::as_u64).unwrap_or(56);
            out.push(format!("`[canvas {w}x{h}]`"));
        }
        "table" => {
            if let Some(headers) = obj.get("headers").and_then(Value::as_array) {
                let mut hdrs = Vec::with_capacity(headers.len());
                for h in headers {
                    hdrs.push(format_terminal_text(Some(h), resolve_sealed));
                }
                out.push(format!("| {} |", hdrs.join(" | ")));
                let mut sep = String::with_capacity(hdrs.len() * 6 + 2);
                sep.push('|');
                for _ in 0..hdrs.len() {
                    sep.push_str(" --- |");
                }
                out.push(sep);
            }
            if let Some(rows) = obj.get("rows").and_then(Value::as_array) {
                for r in rows {
                    if let Some(cells) = r.as_array() {
                        let mut line = Vec::with_capacity(cells.len());
                        for c in cells {
                            line.push(format_terminal_text(Some(c), resolve_sealed));
                        }
                        let mut row_buf = String::with_capacity(line.len() * 8 + 4);
                        row_buf.push_str("| ");
                        for (idx, cell) in line.iter().enumerate() {
                            if idx > 0 {
                                row_buf.push_str(" | ");
                            }
                            let _ = write!(row_buf, "{cell}");
                        }
                        row_buf.push_str(" |");
                        out.push(row_buf);
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
        let _exec_guard = crate::test_wasm_exec_guard();
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
        assert_eq!(
            adapted_card["children"][2]["children"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
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

    #[test]
    fn canvas_primitive_validates_command_budget_and_renders_cleanly() {
        let view = json!({
            "type": "canvas",
            "width": 260,
            "height": 56,
            "tone": "ok",
            "commands": [
                { "op": "clear", "fill": "#0F172A" },
                { "op": "bars", "values": [24.0, 58.0, 94.2], "fill": "#38BDF8" },
                { "op": "text", "text": { "sealed": "h_tps" }, "x": 8, "y": 10 }
            ]
        });
        let resolver = |id: &str| (id == "h_tps").then(|| "94.2 tok/s".to_owned());
        let resolved = resolve_view_tree(&view, resolver).unwrap();
        assert_eq!(resolved["commands"][2]["text"], "94.2 tok/s");
        assert_eq!(resolved["sealed_resolved"], true);

        let term = render_terminal(&view, resolver, false, 60).unwrap();
        assert!(term.contains("94.2 tok/s"));

        // Over 2,000 commands across frame tree must fail validation.
        let over: Vec<Value> = (0..2001)
            .map(|i| json!({ "op": "rect", "x": i, "y": 0, "w": 1, "h": 1 }))
            .collect();
        let bad = json!({ "type": "canvas", "width": 260, "height": 56, "commands": over });
        assert!(adapt_external_ui(&bad).is_err());
    }

    #[test]
    fn malicious_canvas_paint_server_and_unsafe_svg_paths_are_rejected() {
        let evil_fill = json!({
            "type": "canvas",
            "width": 200,
            "height": 60,
            "commands": [
                { "op": "rect", "x": 0, "y": 0, "w": 100, "h": 20, "fill": "url(https://evil.com/leak)" }
            ]
        });
        assert!(matches!(adapt_external_ui(&evil_fill), Err(Error::Package)));

        let evil_stroke = json!({
            "type": "canvas",
            "width": 200,
            "height": 60,
            "commands": [
                { "op": "line", "x1": 0, "y1": 0, "x2": 10, "y2": 10, "stroke": "url(#exfil)" }
            ]
        });
        assert!(matches!(
            adapt_external_ui(&evil_stroke),
            Err(Error::Package)
        ));

        let evil_gradient = json!({
            "type": "canvas",
            "width": 200,
            "height": 60,
            "commands": [
                {
                    "op": "rect",
                    "x": 0,
                    "y": 0,
                    "w": 10,
                    "h": 10,
                    "linearGradient": { "colors": ["#0F172A", "url(https://evil.com/grad)"] }
                }
            ]
        });
        assert!(matches!(
            adapt_external_ui(&evil_gradient),
            Err(Error::Package)
        ));

        let evil_svg_path = json!({
            "type": "canvas",
            "width": 200,
            "height": 60,
            "commands": [
                { "op": "path", "d": "M0 0 L10 10; url(https://evil.com)" }
            ]
        });
        assert!(matches!(
            adapt_external_ui(&evil_svg_path),
            Err(Error::Package)
        ));

        let oversized_svg_path = json!({
            "type": "canvas",
            "width": 200,
            "height": 60,
            "commands": [
                { "op": "path", "d": format!("M0 0 {}", "L1 1 ".repeat(1000)) }
            ]
        });
        assert!(matches!(
            adapt_external_ui(&oversized_svg_path),
            Err(Error::Package)
        ));

        let safe_svg = json!({
            "type": "canvas",
            "width": 200,
            "height": 60,
            "commands": [
                { "op": "path", "d": "M0 0 L100 20 L100 60 Z", "fill": "#38BDF8" }
            ]
        });
        assert!(adapt_external_ui(&safe_svg).is_ok());
    }

    #[test]
    fn malicious_forged_handles_blank_and_terminal_ansi_osc52_are_stripped() {
        let view = json!({
            "type": "column",
            "children": [
                { "type": "heading", "text": "\x1b]52;c;c2VjcmV0X2NsaXBib2FyZA==\x07Safe Heading" },
                { "type": "text", "text": "\x1b[31mRed\x1b[0m \x1b]52;c;YWJj\x1b\\Plain\u{009d}52;c;xyz\u{009c}" },
                { "type": "text", "text": { "sealed": "h_forged" } },
                { "type": "stat", "label": "Host", "value": { "sealed": "h_forged_stat" } },
                {
                    "type": "table",
                    "headers": ["Col"],
                    "rows": [[{ "sealed": "h_forged_cell" }], ["\x1b[2JCell"]]
                },
                {
                    "type": "canvas",
                    "commands": [{ "op": "text", "text": { "sealed": "h_forged_canvas" } }]
                }
            ]
        });
        let resolver = |id: &str| (id == "h_valid").then(|| "ok".to_owned());

        let resolved = resolve_view_tree(&view, resolver).unwrap();
        let resolved_str = resolved.to_string();
        assert!(!resolved_str.contains("h_forged"));
        assert_eq!(resolved["children"][2]["text"], "");
        assert_eq!(resolved["children"][2]["sealed_resolved"], false);
        assert_eq!(resolved["children"][3]["value"], "");
        assert_eq!(resolved["children"][4]["rows"][0][0], "");
        assert_eq!(resolved["children"][5]["commands"][0]["text"], "");

        let term = render_terminal(&view, resolver, false, 80).unwrap();
        assert!(!term.contains('\x1b'));
        assert!(!term.contains('\x07'));
        assert!(!term.contains("52;c;"));
        assert!(!term.contains("c2VjcmV0"));
        assert!(!term.contains("[31m"));
        assert!(!term.contains("[2J"));
        assert!(!term.contains("h_forged"));
        assert!(term.contains("Safe Heading"));
        assert!(term.contains("Red Plain"));
        assert!(term.contains("Cell"));

        // Even when a resolved sealed string contains an OSC 52 escape, render_terminal strips it.
        let sealed_osc_view = json!({
            "type": "text",
            "text": { "sealed": "h_esc" }
        });
        let term_sealed = render_terminal(
            &sealed_osc_view,
            |_| Some("\x1b]52;c;cGF5bG9hZA==\x07secret-host".to_owned()),
            false,
            60,
        )
        .unwrap();
        assert_eq!(term_sealed, "🔒 secret-host");
        assert!(!term_sealed.contains('\x1b'));
        assert!(!term_sealed.contains("52;c;"));
    }

    #[test]
    fn malicious_depth_nodes_and_canvas_budgets_are_rejected() {
        // Depth > MAX_DEPTH (16)
        let mut deep = json!({ "type": "text", "text": "leaf" });
        for _ in 0..17 {
            deep = json!({ "type": "column", "children": [deep] });
        }
        assert!(matches!(adapt_external_ui(&deep), Err(Error::Package)));

        // Node count > MAX_NODES (1024)
        let many_children: Vec<Value> = (0..1025)
            .map(|i| json!({ "type": "text", "text": format!("n{i}") }))
            .collect();
        let wide = json!({ "type": "column", "children": many_children });
        assert!(matches!(adapt_external_ui(&wide), Err(Error::Package)));

        // Canvas command budget > 2000 split across two canvas nodes
        let half_plus: Vec<Value> = (0..1001)
            .map(|i| json!({ "op": "rect", "x": i, "y": 0, "w": 1, "h": 1 }))
            .collect();
        let split_canvas = json!({
            "type": "column",
            "children": [
                { "type": "canvas", "commands": half_plus.clone() },
                { "type": "canvas", "commands": half_plus }
            ]
        });
        assert!(matches!(
            adapt_external_ui(&split_canvas),
            Err(Error::Package)
        ));
    }

    #[test]
    fn malicious_prototype_key_tricks_are_rejected() {
        let proto_node_key = json!({
            "type": "column",
            "__proto__": { "polluted": true },
            "children": []
        });
        assert!(matches!(
            adapt_external_ui(&proto_node_key),
            Err(Error::Package)
        ));

        let constructor_in_args = json!({
            "type": "button",
            "text": "Run",
            "command": "run",
            "args": { "constructor": { "prototype": { "pwn": 1 } } }
        });
        assert!(matches!(
            adapt_external_ui(&constructor_in_args),
            Err(Error::Package)
        ));

        let prototype_in_style = json!({
            "type": "text",
            "text": "hi",
            "style": { "prototype": "bad" }
        });
        assert!(matches!(
            adapt_external_ui(&prototype_in_style),
            Err(Error::Package)
        ));

        for forbidden_handler in [
            "constructor",
            "__proto__",
            "prototype",
            "toString",
            "valueOf",
        ] {
            let bindtap_attack = json!({
                "type": "button",
                "text": "Tap",
                "command": "tap",
                "bindtap": forbidden_handler
            });
            assert!(
                matches!(adapt_external_ui(&bindtap_attack), Err(Error::Package)),
                "bindtap={forbidden_handler} must be rejected"
            );

            let bindinput_attack = json!({
                "type": "input",
                "id": "q",
                "label": "Search",
                "bindinput": forbidden_handler
            });
            assert!(
                matches!(adapt_external_ui(&bindinput_attack), Err(Error::Package)),
                "bindinput={forbidden_handler} must be rejected"
            );
        }

        // CSS url(...) / position: fixed and invalid fontWeight/align values inside style are stripped safely.
        let unsafe_style = json!({
            "type": "text",
            "text": "Styled",
            "tone": "positive",
            "style": {
                "padding": 8,
                "bg": "url(https://evil.com/bg.png)",
                "position": "fixed",
                "fontWeight": "url(https://evil.com/fw)",
                "align": "url(https://evil.com/al)",
                "justify": "space-between",
                "crossAlign": "center"
            }
        });
        let adapted = adapt_external_ui(&unsafe_style).unwrap();
        assert_eq!(adapted["tone"], "ok");
        assert_eq!(adapted["style"]["padding"], 8);
        assert_eq!(adapted["style"]["justify"], "space-between");
        assert_eq!(adapted["style"]["crossAlign"], "center");
        assert!(adapted["style"].get("bg").is_none());
        assert!(adapted["style"].get("position").is_none());
        assert!(adapted["style"].get("fontWeight").is_none());
        assert!(adapted["style"].get("align").is_none());

        // Canonical table, canvas text/width/polygon, option_group, and A2UI Table slots sanitize <script> and enforce bounds.
        let sanitized_slots = adapt_external_ui(&json!({
            "type": "column",
            "children": [
                {
                    "type": "table",
                    "headers": ["Col<script>alert(1)</script>"],
                    "rows": [["javascript:evil()"]]
                },
                {
                    "type": "canvas",
                    "width": 99999,
                    "height": 4,
                    "commands": [
                        { "op": "text", "text": "Hi<ScRiPt>x()</ScRiPt>" }
                    ]
                },
                {
                    "type": "option_group",
                    "id": "opt",
                    "options": [{ "id": "a", "label": "Pick<script>1</script>" }]
                }
            ]
        }))
        .unwrap();
        assert_eq!(sanitized_slots["children"][0]["headers"][0], "Col");
        assert_eq!(sanitized_slots["children"][0]["rows"][0][0], "evil()");
        assert_eq!(sanitized_slots["children"][1]["width"], 2048);
        assert_eq!(sanitized_slots["children"][1]["height"], 16);
        assert_eq!(sanitized_slots["children"][1]["commands"][0]["text"], "Hi");
        assert_eq!(
            sanitized_slots["children"][2]["options"][0]["label"],
            "Pick"
        );

        let bad_polygon = json!({
            "type": "canvas",
            "commands": [
                { "op": "polygon", "points": vec![json!([0, 0]); 513] }
            ]
        });
        assert!(matches!(
            adapt_external_ui(&bad_polygon),
            Err(Error::Package)
        ));
    }
}
