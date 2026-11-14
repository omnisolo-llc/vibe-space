export type Json = null | boolean | number | string | Json[] | {[key: string]: Json};
export type Capability = 'network' | `api:${string}`;
export interface HostPolicy {
  capabilities?: readonly string[];
  methodCapabilities?: Record<string, string>;
}
export type Slot = 'app_page' | 'sidebar_inspector' | 'mobile_bottom_sheet' | 'quick_command' | 'status_bar_item' | 'terminal_action';
export type TriggerScalar = string | number | boolean;
export type TriggerMatcher =
  | TriggerScalar
  | TriggerScalar[]
  | {exact?:TriggerScalar | null; equals?:TriggerScalar | null; caseSensitive?:boolean}
  | {glob?:string; wildcard?:string; caseSensitive?:boolean}
  | {regex?:string; pattern?:string; caseSensitive?:boolean}
  | {contains:TriggerScalar; caseSensitive?:boolean}
  | {prefix?:string; startsWith?:string; caseSensitive?:boolean}
  | {suffix?:string; endsWith?:string; caseSensitive?:boolean}
  | {exists:boolean}
  | {oneOf?:TriggerScalar[]; in?:TriggerScalar[]; caseSensitive?:boolean};
export interface TriggerCondition {
  always?:boolean;
  program?:TriggerMatcher;
  command?:TriggerMatcher;
  window?:TriggerMatcher;
  surface?:TriggerMatcher;
  windowTitle?:TriggerMatcher;
  cwd?:TriggerMatcher;
  pathPattern?:TriggerMatcher;
  env?:Record<string,TriggerMatcher>;
  context?:Record<string,TriggerMatcher>;
  all?:TriggerCondition[];
  any?:TriggerCondition[];
  not?:TriggerCondition;
}
export interface TriggerContext {
  program?:string;
  command?:string;
  argv?:string[];
  window?:string;
  surface?:string;
  windowTitle?:string;
  cwd?:string;
  env?:Record<string,Json>;
  context?:Record<string,Json>;
  timestampMs?:number;
  [key:string]:unknown;
}
export interface ConditionalVibeEntry {
  id:string;
  title:string;
  subtitle?:string;
  when?:TriggerCondition;
  condition?:TriggerCondition;
  isPreset?:boolean;
  enabled?:boolean;
  pinned?:boolean;
  priority?:number;
  order?:number;
  holdMs?:number;
  [key:string]:unknown;
}
export interface TriggerEvaluationResult<T extends ConditionalVibeEntry = ConditionalVibeEntry> {
  context:TriggerContext;
  activeEntries:T[];
  activeIds:string[];
  newlyTriggeredIds:string[];
  deactivatedIds:string[];
  heldIds:string[];
  changed:boolean;
}
export interface Contribution {id:string; slot:Slot; title:string; command:string; when?:TriggerCondition}
export interface Manifest {
  id:string; version:number; api_version:1; name:string;
  license:'MIT' | 'Apache-2.0' | 'BSD-3-Clause' | 'MIT OR Apache-2.0';
  module_sha256:string; capabilities:Capability[]; network_origins:string[]; contributions:Contribution[];
  when?:TriggerCondition;
}
/** Exact manifest UTF-8 is signed with Ed25519. Binary fields are padded base64. */
export interface SignedPackage {manifest:string; signature:string; module:string}
export interface ApiDescriptor {
  name:string; version:number; title:string; description:string; capability:`api:${string}`;
  read_only:boolean; input_schema:Schema; output_schema:Schema;
}
export interface Invocation {
  api_version:1; command:string; arguments:Record<string,Json>; state?:Json;
  results?:{id:string; value?:Json; error?:string}[];
  host?:{framework_version:string; apis:ApiDescriptor[]};
}
export interface Effect {
  id:string; capability:Capability;
  method:'network.fetch' | 'host.call';
  arguments:Record<string,Json>;
}
export interface SealedHandle {
  sealed:string;
}
export type ViewTone = 'default' | 'ok' | 'warn' | 'danger';
export type ViewTextValue = string | number | SealedHandle;
export interface ViewOption {
  id:string; label:string; value?:string; checked?:boolean; selected?:boolean;
}
export type View =
  | {type:'text' | 'heading' | 'badge'; text:ViewTextValue; tone?:ViewTone; bold?:boolean; italic?:boolean; code?:boolean; strong?:boolean; mono?:boolean}
  | {type:'input'; id:string; label:string; secret?:boolean; multiline?:boolean}
  | {type:'checkbox'; id:string; label:string; checked?:boolean; command?:string}
  | {type:'option_group'; id:string; label?:string; multiSelect?:boolean; command?:string; options:ViewOption[]; autoSubmitTimeoutSeconds?:number}
  | {type:'column' | 'row' | 'card'; children:View[]; tone?:ViewTone}
  | {type:'stat'; label:ViewTextValue; value:ViewTextValue; tone?:ViewTone}
  | {type:'bar'; label:ViewTextValue; value:number; max?:number; caption?:ViewTextValue; tone?:ViewTone; swatch?:string}
  | {type:'sparkline'; values:number[]; tone?:ViewTone}
  | {type:'canvas'; width?:number; height?:number; commands:Record<string,unknown>[]; tone?:ViewTone; bindtap?:string; command?:string}
  | {type:'button'; text:ViewTextValue; command:string; args?:Record<string,Json>; arguments?:Record<string,Json>; tone?:ViewTone}
  | {type:'action'; title:string; command:string; arguments?:Record<string,Json>; tone?:ViewTone}
  | {type:'table'; headers:ViewTextValue[]; rows:(ViewTextValue | boolean | null)[][]; tone?:ViewTone}
  | {type:'divider'} | {type:'progress'; value:number; tone?:ViewTone};
export interface Result {state?:Json; view?:View; effects?:Effect[]}
export interface Schema {
  type:'object' | 'array' | 'string' | 'number' | 'integer' | 'boolean' | 'null';
  properties?:Record<string,Schema>; required?:string[]; additionalProperties?:boolean;
  items?:Schema; enum?:Json[]; minimum?:number; maximum?:number;
  minLength?:number; maxLength?:number; maxItems?:number; description?:string;
}
export const slots:readonly Slot[];
export function validApiName(value:unknown):boolean;
export function validCapability(value:unknown,policy?:HostPolicy):boolean;
export function effectCapability(effect:Effect,policy?:HostPolicy):Capability;
export function effectBatch(effects:Effect[],policy?:HostPolicy):readonly Readonly<Effect>[];
export function freezeJson<T extends Json>(value:T):Readonly<T>;
export function validateManifest(manifest:unknown,policy?:HostPolicy):Readonly<Manifest>;
export function verifyPackage(pkg:SignedPackage,publisher:string,policy?:HostPolicy):Promise<{manifest:Readonly<Manifest>;module:Uint8Array}>;

export type SealedResolver = (handleId:string, rawHandle?:SealedHandle) => string | null | undefined;
export interface VibeStrings {
  locale:string; rtl:boolean; [key:string]:string | boolean;
}
export function isSealedHandle(value:unknown):value is SealedHandle;
export function adaptExternalUi(raw:unknown):View;
export function resolveViewTree(view:unknown, options?:{resolveSealed?:SealedResolver}):Record<string,unknown>;
export function renderWithH<TNode = unknown>(
  h:(tag:string, props:Record<string,unknown> | null, ...children:unknown[]) => TNode,
  view:unknown,
  options?:{
    resolveSealed?:SealedResolver;
    onCommand?:(command:string, args:Record<string,unknown>) => void;
    onInput?:(id:string, value:unknown) => void;
    classPrefix?:string;
  }
):TNode;
export function renderToTerminal(view:unknown, options?:{resolveSealed?:SealedResolver; ansi?:boolean; width?:number}):string;
export function renderToMarkdown(view:unknown, options?:{resolveSealed?:SealedResolver}):string;
export function renderToHtmlString(view:unknown, options?:{resolveSealed?:SealedResolver}):string;
export function defineVibeWebComponents(env?:Record<string,unknown>):boolean | Record<string,unknown>;
export function getVibeStrings(locale?:string, overrides?:Record<string,string | boolean>):VibeStrings;
export function isRtlLocale(locale?:string):boolean;
export function validateTriggerCondition(condition:unknown, depth?:number):TriggerCondition;
export function evaluateTriggerCondition(condition:TriggerCondition, context?:TriggerContext):boolean;
export function hydrateVibeTemplate(template:string, context?:TriggerContext, options?:{escapeHtml?:boolean; escapeJson?:boolean}):string;
export function createTriggerEvaluator():{
  dismiss(id:string):void;
  undismiss(id:string):void;
  reset():void;
  evaluate<T extends ConditionalVibeEntry>(entries:Iterable<T>, context?:TriggerContext, nowMs?:number):TriggerEvaluationResult<T>;
};

export const MAX_SET_DATA_BYTES:number;
export const MAX_SET_DATA_RATE_PER_SEC:number;
export const MAX_CANVAS_COMMANDS:number;
export function validateMiniProgramSource(source:string):boolean;
export function applySetData(currentData:Record<string,unknown>, patch:Record<string,unknown>):Record<string,unknown>;
export function lookupScopePath(scope:Record<string,unknown>, expr:string):unknown;
export function compileTemplate(template:Record<string,unknown>, scope?:Record<string,unknown>):View;
export function defineMiniProgram(spec:Record<string,unknown>):Record<string,unknown>;
export function createMiniProgramSession(definition:Record<string,unknown>, options?:{template?:Record<string,unknown>; maxRatePerSec?:number}):{
  readonly data:Record<string,unknown>;
  readonly lifecycle:string;
  setData(patch:Record<string,unknown>, nowMs?:number):void;
  load(initialHostData?:Record<string,unknown>, initialContext?:TriggerContext):void;
  updateHostData(nextHostData?:Record<string,unknown>, nextContext?:TriggerContext):void;
  dispatchEvent(event:{type:string; handler:string; target?:Record<string,unknown>; detail?:Record<string,unknown>}):boolean;
  hide():void;
  buildView():View | null;
};
