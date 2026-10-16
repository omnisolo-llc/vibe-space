export type Json = null | boolean | number | string | Json[] | {[key: string]: Json};
export type Capability = 'network' | 'terminal_read' | 'terminal_write' | `api:${string}`;
export type Slot = 'app_page' | 'sidebar_inspector' | 'mobile_bottom_sheet' | 'quick_command' | 'status_bar_item' | 'terminal_action';
export interface Contribution {id:string; slot:Slot; title:string; command:string}
export interface Manifest {
  id:string; version:number; api_version:1; name:string;
  license:'MIT' | 'Apache-2.0' | 'BSD-3-Clause' | 'MIT OR Apache-2.0';
  module_sha256:string; capabilities:Capability[]; network_origins:string[]; contributions:Contribution[];
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
  method:'network.fetch' | 'terminal.read' | 'terminal.write' | 'host.call';
  arguments:Record<string,Json>;
}
export type View =
  | {type:'text' | 'heading' | 'badge'; text:string; bold?:boolean; italic?:boolean; code?:boolean}
  | {type:'input'; id:string; label:string; secret?:boolean; multiline?:boolean}
  | {type:'column' | 'row' | 'card'; children:View[]}
  | {type:'action'; title:string; command:string; arguments?:Record<string,Json>}
  | {type:'divider'} | {type:'progress'; value:number};
export interface Result {state?:Json; view?:View; effects?:Effect[]}
export interface Schema {
  type:'object' | 'array' | 'string' | 'number' | 'integer' | 'boolean' | 'null';
  properties?:Record<string,Schema>; required?:string[]; additionalProperties?:boolean;
  items?:Schema; enum?:Json[]; minimum?:number; maximum?:number;
  minLength?:number; maxLength?:number; maxItems?:number; description?:string;
}
export const slots:readonly Slot[];
export function validApiName(value:unknown):boolean;
export function validCapability(value:unknown):boolean;
export function effectCapability(effect:Effect):Capability;
export function effectBatch(effects:Effect[]):readonly Readonly<Effect>[];
export function freezeJson<T extends Json>(value:T):Readonly<T>;
export function validateManifest(manifest:unknown):Readonly<Manifest>;
export function verifyPackage(pkg:SignedPackage,publisher:string):Promise<{manifest:Readonly<Manifest>;module:Uint8Array}>;
