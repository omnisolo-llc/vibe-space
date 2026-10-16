//! Optional signed Wasm packages. No WASI, ambient imports, JIT or bundled plugins.
use base64::{Engine as _, engine::general_purpose::STANDARD};
use ed25519_dalek::{Signature, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};
use wasmi::{
    Config, EnforcedLimits, Engine, Linker, Module, Store, StoreLimits, StoreLimitsBuilder,
};

pub const MAX_MODULE_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_MESSAGE_BYTES: usize = 1024 * 1024;
pub const API_VERSION: u32 = 1;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid or incompatible plugin package")]
    Package,
    #[error("plugin permission denied")]
    Permission,
    #[error("plugin execution failed: {0}")]
    Runtime(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub struct Manifest {
    pub id: String,
    pub version: u64,
    pub api_version: u32,
    pub name: String,
    pub license: String,
    pub module_sha256: String,
    pub capabilities: BTreeSet<String>,
    #[serde(default)]
    pub network_origins: BTreeSet<String>,
    #[serde(default)]
    pub contributions: Vec<Contribution>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Contribution {
    pub id: String,
    pub slot: String,
    pub title: String,
    pub command: String,
}

#[derive(Clone, Deserialize, Serialize)]
pub struct SignedPackage {
    /// Exact signed UTF-8 bytes, never parse/reserialize before verification.
    pub manifest: String,
    pub signature: String,
    pub module: String,
}

#[derive(Clone, Deserialize, Serialize)]
pub struct InstalledPlugin {
    pub manifest: Manifest,
    pub enabled: bool,
    pub grants: BTreeSet<String>,
    /// Changes on every install, grant, enable and disable operation.
    #[serde(default)]
    pub revision: String,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SealedDiskPackage {
    manifest: String,
    signature: String,
    sealed_module: String,
    seal_tag: String,
}

/// API v1 effects implemented by the app host. Resource-scoped filesystem and
/// vault access are not supported and must not be accepted as permissions.
pub const SUPPORTED_CAPABILITIES: &[&str] = &["network", "terminal_read", "terminal_write"];

/// Host APIs are namespaced and granted independently. No host handler is
/// installed by accepting a manifest; the embedding app registers implementations.
pub fn valid_api_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 128
        && name.split('.').all(|part| {
            !part.is_empty()
                && part
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        })
}

fn new_revision() -> Result<String, Error> {
    let mut bytes = [0; 24];
    getrandom::fill(&mut bytes).map_err(|e| Error::Runtime(e.to_string()))?;
    Ok(STANDARD.encode(bytes))
}

// Bound all tenants together, including compilation. Fail busy rather than
// growing an unbounded blocking-thread queue or serializing unrelated hosts.
static ACTIVE_EXECUTIONS: AtomicUsize = AtomicUsize::new(0);
struct ExecutionPermit;
impl ExecutionPermit {
    fn acquire() -> Result<Self, Error> {
        ACTIVE_EXECUTIONS
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |n| {
                (n < 4).then_some(n + 1)
            })
            .map(|_| Self)
            .map_err(|_| Error::Runtime("extension runtime busy".into()))
    }
}
impl Drop for ExecutionPermit {
    fn drop(&mut self) {
        ACTIVE_EXECUTIONS.fetch_sub(1, Ordering::AcqRel);
    }
}

/// Derive authority from the method and API name, never the supplied capability.
pub fn effect_capability(effect: &serde_json::Value) -> Result<(String, bool), Error> {
    let method = effect
        .get("method")
        .and_then(|v| v.as_str())
        .ok_or(Error::Permission)?;
    let (capability, read_only) = match method {
        "network.fetch" => ("network".to_owned(), false),
        "terminal.read" => ("terminal_read".to_owned(), true),
        "terminal.write" => ("terminal_write".to_owned(), false),
        "host.call" => {
            let api = effect
                .pointer("/arguments/api")
                .and_then(|v| v.as_str())
                .ok_or(Error::Permission)?;
            if !valid_api_name(api) {
                return Err(Error::Permission);
            }
            (format!("api:{api}"), false)
        }
        _ => return Err(Error::Permission),
    };
    if effect.get("capability").and_then(|v| v.as_str()) != Some(capability.as_str()) {
        return Err(Error::Permission);
    }
    Ok((capability, read_only))
}

const PLUGIN_POLICY_TABLE_RAW: &[u8; 159] = b"network|terminal_read|terminal_write|MIT|Apache-2.0|BSD-3-Clause|MIT OR Apache-2.0|network.fetch|terminal.read|terminal.write|omniterm.plugin-runtime.policy.v1";

const PLUGIN_VM_INSN_BYTES: usize = 8;

#[derive(Clone, Copy)]
enum PluginVmOp {
    MatchSegment { dst: u8, sep: u8 },
    XorImm { dst: u8, imm: u32 },
    RolImm { dst: u8, bits: u8 },
    Halt { src: u8 },
}

struct SealedPluginPolicyVm<const CODE_N: usize, const DATA_N: usize> {
    domain: &'static [u8],
    key_share_a: [u8; 32],
    key_share_b: [u8; 32],
    code_ciphertext: [u8; CODE_N],
    data_ciphertext: [u8; DATA_N],
    integrity_tag: [u8; 32],
}

const fn plugin_vm_stream_byte(
    share_a: &[u8; 32],
    share_b: &[u8; 32],
    domain: &[u8],
    phase: u8,
    idx: usize,
) -> u8 {
    let a = share_a[idx & 31];
    let b = share_b[(idx.wrapping_mul(7).wrapping_add(phase as usize)) & 31];
    let d = domain[idx % domain.len()];
    let mix = (idx as u8)
        .wrapping_mul(0x9E)
        .wrapping_add(phase.rotate_left(3))
        ^ d.rotate_left((idx & 7) as u32);
    a ^ b ^ mix
}

const fn compute_plugin_vm_tag<const CODE_N: usize, const DATA_N: usize>(
    share_a: &[u8; 32],
    share_b: &[u8; 32],
    domain: &[u8],
    code_ct: &[u8; CODE_N],
    data_ct: &[u8; DATA_N],
) -> [u8; 32] {
    let mut tag = [0_u8; 32];
    let mut i = 0usize;
    while i < 32 {
        tag[i] = share_a[i] ^ share_b[31 - i] ^ domain[i % domain.len()];
        i += 1;
    }
    let mut j = 0usize;
    while j < CODE_N {
        let lane = j & 31;
        tag[lane] = tag[lane]
            .wrapping_add(code_ct[j] ^ (j as u8))
            .rotate_left(3);
        j += 1;
    }
    let mut k = 0usize;
    while k < DATA_N {
        let lane = (k.wrapping_mul(5)) & 31;
        tag[lane] = tag[lane]
            .wrapping_add(data_ct[k] ^ (k as u8).wrapping_mul(13))
            .rotate_left(5);
        k += 1;
    }
    tag
}

const fn compile_plugin_policy_vm<
    const PROG_LEN: usize,
    const CODE_N: usize,
    const DATA_N: usize,
>(
    prog: &[PluginVmOp; PROG_LEN],
    data: &[u8; DATA_N],
    key_share_a: [u8; 32],
    key_share_b: [u8; 32],
    domain: &'static [u8],
) -> SealedPluginPolicyVm<CODE_N, DATA_N> {
    assert!(CODE_N == PROG_LEN * PLUGIN_VM_INSN_BYTES);
    let mut code_ct = [0_u8; CODE_N];
    let mut pc = 0usize;
    while pc < PROG_LEN {
        let raw: [u8; PLUGIN_VM_INSN_BYTES] = match prog[pc] {
            PluginVmOp::MatchSegment { dst, sep } => [0xA1, dst, sep, 0, 0, 0, 0, 0],
            PluginVmOp::XorImm { dst, imm } => {
                let b = imm.to_le_bytes();
                [0xB2, dst, 0, 0, b[0], b[1], b[2], b[3]]
            }
            PluginVmOp::RolImm { dst, bits } => [0xC3, dst, bits, 0, 0, 0, 0, 0],
            PluginVmOp::Halt { src } => [0xD4, src, 0, 0, 0, 0, 0, 0],
        };
        let base = pc * PLUGIN_VM_INSN_BYTES;
        let mut idx = 0usize;
        while idx < PLUGIN_VM_INSN_BYTES {
            let mask = plugin_vm_stream_byte(&key_share_a, &key_share_b, domain, 0x31, base + idx);
            code_ct[base + idx] = raw[idx] ^ mask;
            idx += 1;
        }
        pc += 1;
    }
    let mut data_ct = [0_u8; DATA_N];
    let mut d_idx = 0usize;
    while d_idx < DATA_N {
        let mask = plugin_vm_stream_byte(&key_share_a, &key_share_b, domain, 0x7A, d_idx);
        data_ct[d_idx] = data[d_idx] ^ mask;
        d_idx += 1;
    }
    let integrity_tag =
        compute_plugin_vm_tag(&key_share_a, &key_share_b, domain, &code_ct, &data_ct);
    SealedPluginPolicyVm {
        domain,
        key_share_a,
        key_share_b,
        code_ciphertext: code_ct,
        data_ciphertext: data_ct,
        integrity_tag,
    }
}

impl<const CODE_N: usize, const DATA_N: usize> SealedPluginPolicyVm<CODE_N, DATA_N> {
    fn execute(&self, mode: u8, input: &[u8], seed: u64) -> Result<u64, Error> {
        if mode > 3 {
            return Err(Error::Package);
        }
        let expected = compute_plugin_vm_tag(
            &self.key_share_a,
            &self.key_share_b,
            self.domain,
            &self.code_ciphertext,
            &self.data_ciphertext,
        );
        let mut diff = 0_u8;
        for (a, b) in expected.iter().zip(self.integrity_tag.iter()) {
            diff |= a ^ b;
        }
        if diff != 0 {
            return Err(Error::Package);
        }
        let mut code_plain = WipingBuffer(vec![0_u8; CODE_N]);
        for i in 0..CODE_N {
            code_plain.0[i] = self.code_ciphertext[i]
                ^ plugin_vm_stream_byte(&self.key_share_a, &self.key_share_b, self.domain, 0x31, i);
        }
        let mut data_plain = WipingBuffer(vec![0_u8; DATA_N]);
        for i in 0..DATA_N {
            data_plain.0[i] = self.data_ciphertext[i]
                ^ plugin_vm_stream_byte(&self.key_share_a, &self.key_share_b, self.domain, 0x7A, i);
        }
        let mut regs = [0_u64; 4];
        regs[0] = u64::from(mode);
        regs[2] = seed;
        let mut pc = 0usize;
        let prog_len = CODE_N / PLUGIN_VM_INSN_BYTES;
        while pc < prog_len {
            let base = pc * PLUGIN_VM_INSN_BYTES;
            let op = code_plain.0[base];
            let reg = (code_plain.0[base + 1] as usize) & 3;
            match op {
                0xA1 => {
                    let sep = code_plain.0[base + 2];
                    let mut matched = 0_u64;
                    for (seg_idx, candidate) in (1_u64..).zip(data_plain.0.split(|&b| b == sep)) {
                        if mode == 3 {
                            if seg_idx == 11 {
                                let mut acc = regs[2] ^ 0x504C_4756_4D50_534C_u64;
                                for (idx, &b) in candidate.iter().enumerate() {
                                    acc ^= u64::from(b)
                                        .wrapping_add((idx as u64).wrapping_mul(0x9E37_79B9));
                                    acc = acc.rotate_left(13).wrapping_mul(0xBF58_476D_1CE4_E5B9);
                                }
                                matched = acc ^ seg_idx;
                            }
                        } else {
                            let in_domain = match mode {
                                0 => (1..=3).contains(&seg_idx),
                                1 => (4..=7).contains(&seg_idx),
                                2 => (8..=10).contains(&seg_idx),
                                _ => false,
                            };
                            let mut eq_diff = candidate.len() ^ input.len();
                            let max_len = candidate.len().max(input.len());
                            for idx in 0..max_len {
                                let x = candidate.get(idx).copied().unwrap_or(0);
                                let y = input.get(idx).copied().unwrap_or(0);
                                eq_diff |= usize::from(x ^ y);
                            }
                            if in_domain && eq_diff == 0 && matched == 0 {
                                matched = seg_idx;
                            }
                        }
                    }
                    regs[reg] = matched;
                }
                0xB2 => {
                    let imm = u32::from_le_bytes([
                        code_plain.0[base + 4],
                        code_plain.0[base + 5],
                        code_plain.0[base + 6],
                        code_plain.0[base + 7],
                    ]) as u64;
                    regs[reg] ^= imm ^ regs[2] ^ (regs[0] << 32);
                }
                0xC3 => {
                    let bits = u32::from(code_plain.0[base + 2] & 63);
                    regs[reg] = regs[reg].rotate_left(bits);
                }
                0xD4 => {
                    let out = regs[reg];
                    for r in &mut regs {
                        *r = std::hint::black_box(0);
                    }
                    return Ok(out);
                }
                _ => return Err(Error::Package),
            }
            pc += 1;
        }
        Err(Error::Package)
    }
}

const PLUGIN_POLICY_VM_PROG: [PluginVmOp; 4] = [
    PluginVmOp::MatchSegment { dst: 1, sep: b'|' },
    PluginVmOp::XorImm {
        dst: 1,
        imm: 0x4F4D_4E50,
    },
    PluginVmOp::RolImm { dst: 1, bits: 11 },
    PluginVmOp::Halt { src: 1 },
];

static PLUGIN_POLICY_VM: SealedPluginPolicyVm<{ 4 * PLUGIN_VM_INSN_BYTES }, 159> =
    compile_plugin_policy_vm(
        &PLUGIN_POLICY_VM_PROG,
        PLUGIN_POLICY_TABLE_RAW,
        [
            0x6C, 0x15, 0xA9, 0xE2, 0x38, 0xD1, 0x47, 0xBC, 0x90, 0x2F, 0x5E, 0x83, 0xC4, 0x1A,
            0x79, 0xF6, 0x0B, 0xD8, 0x42, 0x95, 0xE7, 0x31, 0x64, 0xAF, 0x53, 0x8E, 0x1C, 0xB7,
            0x29, 0xF0, 0x6A, 0xC1,
        ],
        [
            0x93, 0xEA, 0x56, 0x1D, 0xC7, 0x2E, 0xB8, 0x43, 0x6F, 0xD0, 0xA1, 0x7C, 0x3B, 0xE5,
            0x86, 0x09, 0xF4, 0x27, 0xBD, 0x6A, 0x18, 0xCE, 0x9B, 0x50, 0xAC, 0x71, 0xE3, 0x48,
            0xD6, 0x0F, 0x95, 0x3E,
        ],
        b"omniterm.plugin-runtime.vmp.v1",
    );

const fn plugin_vm_token_for_segment(mode: u8, seg: u64, seed: u64) -> u64 {
    (seg ^ 0x4F4D_4E50 ^ seed ^ ((mode as u64) << 32)).rotate_left(11)
}

fn classify_plugin_policy_segment(mode: u8, input: &[u8]) -> Option<u64> {
    let token = PLUGIN_POLICY_VM.execute(mode, input, 0).ok()?;
    let range = match mode {
        0 => 1..=3,
        1 => 4..=7,
        2 => 8..=10,
        _ => return None,
    };
    range
        .into_iter()
        .find(|&seg| token == plugin_vm_token_for_segment(mode, seg, 0))
}

fn is_supported_capability(capability: &str) -> bool {
    if capability.strip_prefix("api:").is_some_and(valid_api_name) {
        return true;
    }
    matches!(
        classify_plugin_policy_segment(0, capability.as_bytes()),
        Some(1..=3)
    )
}

fn is_supported_license(license: &str) -> bool {
    matches!(
        classify_plugin_policy_segment(1, license.as_bytes()),
        Some(4..=7)
    )
}

/// Cryptographic data-flow coupling token derived from executing `PLUGIN_POLICY_VM`
/// on the internal canary segment. Mixed into RAM and disk sealing key derivation.
fn plugin_policy_seal_token() -> [u8; 8] {
    PLUGIN_POLICY_VM
        .execute(3, b"", 0x4F4D_4E50_564D_5031)
        .unwrap_or(0)
        .to_le_bytes()
}

fn safe_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && !id.starts_with('.')
        && id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b".-_".contains(&c))
}

struct WipingBuffer(Vec<u8>);

impl Drop for WipingBuffer {
    fn drop(&mut self) {
        for byte in &mut self.0 {
            // Volatile-style write through black_box prevents dead-store elimination.
            *byte = std::hint::black_box(0);
        }
        std::sync::atomic::compiler_fence(std::sync::atomic::Ordering::SeqCst);
    }
}

/// Wasm module held as two XOR shares in memory.
///
/// The raw `\0asm` bytecode is XOR-split across two independent heap buffers
/// (`masked` and `mask`) and verified against `expected_sha256` on each
/// transient unsealing window.
pub struct SealedWasmModule {
    masked: Vec<u8>,
    mask: Vec<u8>,
    expected_sha256: [u8; 32],
}

impl SealedWasmModule {
    /// Seals a verified Wasm module into two independent XOR shares and wipes
    /// the caller's plaintext `module_bytes` vector in-place.
    #[must_use]
    pub fn seal(module_bytes: Vec<u8>, context_seed: &[u8]) -> Self {
        let module_bytes = WipingBuffer(module_bytes);
        let expected_sha256: [u8; 32] = Sha256::digest(&module_bytes.0).into();
        let len = module_bytes.0.len();
        let mut mask = WipingBuffer(vec![0_u8; len]);
        let mut masked = WipingBuffer(vec![0_u8; len]);
        let mut offset = 0usize;
        let mut counter = 0u64;
        let addr_entropy = (&raw const module_bytes as usize).to_le_bytes();
        let vm_token = plugin_policy_seal_token();
        while offset < len {
            let mut hasher = Sha256::new();
            hasher.update(b"omniterm.plugin-runtime.wasm-seal.v1\0");
            hasher.update(vm_token);
            hasher.update(context_seed);
            hasher.update(expected_sha256);
            hasher.update(addr_entropy);
            hasher.update(counter.to_le_bytes());
            let block: [u8; 32] = hasher.finalize().into();
            let take = (len - offset).min(32);
            for (i, &byte) in block.iter().take(take).enumerate() {
                mask.0[offset + i] = byte;
                masked.0[offset + i] = module_bytes.0[offset + i] ^ byte;
            }
            offset += take;
            counter = counter.wrapping_add(1);
        }
        Self {
            masked: std::mem::take(&mut masked.0),
            mask: std::mem::take(&mut mask.0),
            expected_sha256,
        }
    }

    /// Returns the encrypted share length in bytes.
    #[must_use]
    pub fn len(&self) -> usize {
        self.masked.len()
    }

    /// Returns true if the sealed module is empty.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.masked.is_empty()
    }

    /// Reconstructs the Wasm bytecode inside a short-lived [`WipingBuffer`],
    /// compares its SHA-256 digest without an early exit, invokes `f`, and wipes
    /// the transient plaintext buffer on return or unwind. Both shares are
    /// retained in this process; they do not protect against a memory reader.
    pub fn with_decrypted_bytes<R>(
        &self,
        f: impl FnOnce(&[u8]) -> Result<R, Error>,
    ) -> Result<R, Error> {
        if self.masked.len() != self.mask.len() || self.masked.len() > MAX_MODULE_BYTES {
            return Err(Error::Package);
        }
        let mut unmasked = WipingBuffer(vec![0_u8; self.masked.len()]);
        for i in 0..self.masked.len() {
            unmasked.0[i] = self.masked[i] ^ self.mask[i];
        }
        let digest: [u8; 32] = Sha256::digest(&unmasked.0).into();
        let mut diff = 0_u8;
        for (a, b) in digest.iter().zip(self.expected_sha256.iter()) {
            diff |= a ^ b;
        }
        if diff != 0 {
            return Err(Error::Package);
        }
        f(&unmasked.0)
    }

    #[cfg(test)]
    #[must_use]
    pub(crate) fn masked_share(&self) -> &[u8] {
        &self.masked
    }
}

impl Drop for SealedWasmModule {
    fn drop(&mut self) {
        for byte in &mut self.masked {
            *byte = std::hint::black_box(0);
        }
        for byte in &mut self.mask {
            *byte = std::hint::black_box(0);
        }
        for byte in &mut self.expected_sha256 {
            *byte = std::hint::black_box(0);
        }
        std::sync::atomic::compiler_fence(std::sync::atomic::Ordering::SeqCst);
    }
}

fn seal_disk_package(
    package: &SignedPackage,
    publisher: &[u8; 32],
    raw_module: &[u8],
) -> SealedDiskPackage {
    let vm_token = plugin_policy_seal_token();
    let sig_bytes = package.signature.as_bytes();
    let manifest_bytes = package.manifest.as_bytes();
    let mut masked = WipingBuffer(vec![0_u8; raw_module.len()]);
    let mut offset = 0usize;
    let mut counter = 0u64;
    while offset < raw_module.len() {
        let mut hasher = Sha256::new();
        hasher.update(b"omniterm.plugin-runtime.disk-seal.v1\0");
        hasher.update(vm_token);
        hasher.update(publisher);
        hasher.update((sig_bytes.len() as u64).to_le_bytes());
        hasher.update(sig_bytes);
        hasher.update((manifest_bytes.len() as u64).to_le_bytes());
        hasher.update(manifest_bytes);
        hasher.update(counter.to_le_bytes());
        let block: [u8; 32] = hasher.finalize().into();
        let take = (raw_module.len() - offset).min(32);
        for (i, &k) in block.iter().take(take).enumerate() {
            masked.0[offset + i] = raw_module[offset + i] ^ k;
        }
        offset += take;
        counter = counter.wrapping_add(1);
    }
    let mut tag_hasher = Sha256::new();
    tag_hasher.update(b"omniterm.plugin-runtime.disk-tag.v1\0");
    tag_hasher.update(vm_token);
    tag_hasher.update(publisher);
    tag_hasher.update((sig_bytes.len() as u64).to_le_bytes());
    tag_hasher.update(sig_bytes);
    tag_hasher.update((manifest_bytes.len() as u64).to_le_bytes());
    tag_hasher.update(manifest_bytes);
    tag_hasher.update((masked.0.len() as u64).to_le_bytes());
    tag_hasher.update(&masked.0);
    let tag: [u8; 32] = tag_hasher.finalize().into();
    SealedDiskPackage {
        manifest: package.manifest.clone(),
        signature: package.signature.clone(),
        sealed_module: STANDARD.encode(&masked.0),
        seal_tag: STANDARD.encode(tag),
    }
}

fn unseal_disk_package(
    disk: &SealedDiskPackage,
    publisher: &[u8; 32],
) -> Result<SignedPackage, Error> {
    if disk.manifest.len() > 64 * 1024
        || disk.sealed_module.len() > 4 * MAX_MODULE_BYTES.div_ceil(3)
        || disk.signature.len() != 88
    {
        return Err(Error::Package);
    }
    let masked = WipingBuffer(
        STANDARD
            .decode(&disk.sealed_module)
            .map_err(|_| Error::Package)?,
    );
    let provided_tag = STANDARD
        .decode(&disk.seal_tag)
        .map_err(|_| Error::Package)?;
    if provided_tag.len() != 32 {
        return Err(Error::Package);
    }
    let vm_token = plugin_policy_seal_token();
    let sig_bytes = disk.signature.as_bytes();
    let manifest_bytes = disk.manifest.as_bytes();
    let mut tag_hasher = Sha256::new();
    tag_hasher.update(b"omniterm.plugin-runtime.disk-tag.v1\0");
    tag_hasher.update(vm_token);
    tag_hasher.update(publisher);
    tag_hasher.update((sig_bytes.len() as u64).to_le_bytes());
    tag_hasher.update(sig_bytes);
    tag_hasher.update((manifest_bytes.len() as u64).to_le_bytes());
    tag_hasher.update(manifest_bytes);
    tag_hasher.update((masked.0.len() as u64).to_le_bytes());
    tag_hasher.update(&masked.0);
    let expected_tag: [u8; 32] = tag_hasher.finalize().into();
    let mut diff = 0_u8;
    for (a, b) in expected_tag.iter().zip(provided_tag.iter()) {
        diff |= a ^ b;
    }
    if diff != 0 {
        return Err(Error::Package);
    }
    let mut plain = WipingBuffer(vec![0_u8; masked.0.len()]);
    let mut offset = 0usize;
    let mut counter = 0u64;
    while offset < masked.0.len() {
        let mut hasher = Sha256::new();
        hasher.update(b"omniterm.plugin-runtime.disk-seal.v1\0");
        hasher.update(vm_token);
        hasher.update(publisher);
        hasher.update((sig_bytes.len() as u64).to_le_bytes());
        hasher.update(sig_bytes);
        hasher.update((manifest_bytes.len() as u64).to_le_bytes());
        hasher.update(manifest_bytes);
        hasher.update(counter.to_le_bytes());
        let block: [u8; 32] = hasher.finalize().into();
        let take = (masked.0.len() - offset).min(32);
        for (i, &k) in block.iter().take(take).enumerate() {
            plain.0[offset + i] = masked.0[offset + i] ^ k;
        }
        offset += take;
        counter = counter.wrapping_add(1);
    }
    Ok(SignedPackage {
        manifest: disk.manifest.clone(),
        signature: disk.signature.clone(),
        module: STANDARD.encode(&plain.0),
    })
}

pub fn verify(package: &SignedPackage, publisher: &[u8; 32]) -> Result<(Manifest, Vec<u8>), Error> {
    if package.manifest.len() > 64 * 1024
        || package.module.len() > 4 * MAX_MODULE_BYTES.div_ceil(3)
        || package.signature.len() != 88
    {
        return Err(Error::Package);
    }
    let key = VerifyingKey::from_bytes(publisher).map_err(|_| Error::Package)?;
    let signature = STANDARD
        .decode(&package.signature)
        .map_err(|_| Error::Package)?;
    let signature = Signature::from_slice(&signature).map_err(|_| Error::Package)?;
    key.verify_strict(package.manifest.as_bytes(), &signature)
        .map_err(|_| Error::Package)?;
    let manifest: Manifest = serde_json::from_str(&package.manifest)?;
    if !safe_id(&manifest.id)
        || manifest.api_version != API_VERSION
        || manifest.version == 0
        || manifest.version > 9_007_199_254_740_991
        || manifest.name.is_empty()
        || manifest.name.len() > 256
        || manifest.capabilities.len() > 64
        || !manifest
            .capabilities
            .iter()
            .all(|c| is_supported_capability(c))
    {
        return Err(Error::Package);
    }
    if !is_supported_license(&manifest.license) {
        return Err(Error::Package);
    }
    if manifest.network_origins.len() > 32 || manifest.contributions.len() > 64 {
        return Err(Error::Package);
    }
    for origin in &manifest.network_origins {
        let url = url::Url::parse(origin).map_err(|_| Error::Package)?;
        if url.scheme() != "https"
            || !url.username().is_empty()
            || url.password().is_some()
            || url.origin().ascii_serialization() != *origin
        {
            return Err(Error::Package);
        }
    }
    let mut contribution_ids = BTreeSet::new();
    for c in &manifest.contributions {
        if ![
            "app_page",
            "sidebar_inspector",
            "mobile_bottom_sheet",
            "quick_command",
            "status_bar_item",
            "terminal_action",
        ]
        .contains(&c.slot.as_str())
            || [&c.id, &c.title, &c.command]
                .iter()
                .any(|s| s.is_empty() || s.len() > 256)
            || !contribution_ids.insert(&c.id)
        {
            return Err(Error::Package);
        }
    }
    let mut module = WipingBuffer(
        STANDARD
            .decode(&package.module)
            .map_err(|_| Error::Package)?,
    );
    if module.0.len() > MAX_MODULE_BYTES
        || !module.0.starts_with(b"\0asm")
        || STANDARD.encode(Sha256::digest(&module.0)) != manifest.module_sha256
    {
        return Err(Error::Package);
    }
    Ok((manifest, std::mem::take(&mut module.0)))
}

/// Verifies a signed plugin package and immediately seals the decoded Wasm
/// bytecode into a [`SealedWasmModule`], wiping the intermediate plaintext buffer.
pub fn verify_sealed(
    package: &SignedPackage,
    publisher: &[u8; 32],
) -> Result<(Manifest, SealedWasmModule), Error> {
    let (manifest, module) = verify(package, publisher)?;
    let mut module = WipingBuffer(module);
    let mut context_seed = Vec::with_capacity(32 + package.signature.len());
    context_seed.extend_from_slice(publisher);
    context_seed.extend_from_slice(package.signature.as_bytes());
    let sealed = SealedWasmModule::seal(std::mem::take(&mut module.0), &context_seed);
    Ok((manifest, sealed))
}

fn validate_ui_resource_descriptor(ui_resource: &serde_json::Value) -> Result<(), Error> {
    let obj = ui_resource.as_object().ok_or(Error::Permission)?;
    let uri = obj
        .get("uri")
        .and_then(|v| v.as_str())
        .ok_or(Error::Permission)?;
    let Some(view_file) = uri.strip_prefix("ui://omniterm/") else {
        return Err(Error::Permission);
    };
    let Some(stem) = view_file.strip_suffix(".html") else {
        return Err(Error::Permission);
    };
    if !safe_id(stem) || stem.contains('.') {
        return Err(Error::Permission);
    }
    if let Some(mime) = obj.get("mime_type")
        && mime.as_str() != Some("text/html;profile=mcp-app")
    {
        return Err(Error::Permission);
    }
    Ok(())
}

/// The caller supplies a publisher key from a host-managed trust store, never the package.
pub struct PackageStore {
    root: PathBuf,
}
impl PackageStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    fn lock(&self) -> Result<fs::File, Error> {
        fs::create_dir_all(&self.root)?;
        let lock = fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(self.root.join(".registry.lock"))?;
        lock.lock()?;
        Ok(lock)
    }

    pub fn install(
        &self,
        package: &SignedPackage,
        publisher: &[u8; 32],
    ) -> Result<InstalledPlugin, Error> {
        let _lock = self.lock()?;
        let (manifest, module) = verify(package, publisher)?;
        let module = WipingBuffer(module);
        let sealed_disk = seal_disk_package(package, publisher, &module.0);
        drop(module);
        let old = self.load(&manifest.id).ok();
        if old
            .as_ref()
            .is_some_and(|p| p.manifest.version >= manifest.version)
        {
            return Err(Error::Package);
        }
        if let Some(old) = &old {
            let pinned = fs::read(
                self.root
                    .join(&manifest.id)
                    .join(old.manifest.version.to_string())
                    .join("publisher.key"),
            )?;
            if pinned != publisher {
                return Err(Error::Package);
            }
        }
        let dir = self.root.join(&manifest.id);
        fs::create_dir_all(&dir)?;
        let revision = dir.join(manifest.version.to_string());
        fs::create_dir(&revision)?;
        fs::write(
            revision.join("package.json"),
            serde_json::to_vec(&sealed_disk)?,
        )?;
        fs::write(revision.join("publisher.key"), publisher)?;
        // Updates always disable the plugin. New capabilities never inherit approval.
        let installed = InstalledPlugin {
            manifest,
            enabled: false,
            grants: BTreeSet::new(),
            revision: new_revision()?,
        };
        self.save(&installed)?;
        Ok(installed)
    }

    pub fn load(&self, id: &str) -> Result<InstalledPlugin, Error> {
        if !safe_id(id) {
            return Err(Error::Package);
        }
        let mut value: InstalledPlugin =
            serde_json::from_slice(&fs::read(self.root.join(id).join("installed.json"))?)?;
        if value.manifest.id != id {
            return Err(Error::Package);
        }
        let revision = self.root.join(id).join(value.manifest.version.to_string());
        let disk_bytes = fs::read(revision.join("package.json")).map_err(|_| Error::Package)?;
        let _sealed_disk: SealedDiskPackage =
            serde_json::from_slice(&disk_bytes).map_err(|_| Error::Package)?;
        if value.revision.is_empty() {
            value.enabled = false;
            value.grants.clear();
        }
        Ok(value)
    }

    fn save(&self, installed: &InstalledPlugin) -> Result<(), Error> {
        let dir = self.root.join(&installed.manifest.id);
        let temp = dir.join("installed.tmp");
        fs::write(&temp, serde_json::to_vec(installed)?)?;
        fs::rename(temp, dir.join("installed.json"))?;
        Ok(())
    }

    pub fn enable(&self, id: &str, grants: BTreeSet<String>) -> Result<(), Error> {
        let _lock = self.lock()?;
        let mut plugin = self.load(id)?;
        if !grants.is_subset(&plugin.manifest.capabilities)
            || !grants.iter().all(|c| is_supported_capability(c))
        {
            return Err(Error::Permission);
        }
        plugin.grants = grants;
        plugin.enabled = true;
        plugin.revision = new_revision()?;
        self.save(&plugin)
    }

    pub fn disable(&self, id: &str) -> Result<(), Error> {
        let _lock = self.lock()?;
        let mut plugin = self.load(id)?;
        plugin.enabled = false;
        plugin.grants.clear();
        plugin.revision = new_revision()?;
        self.save(&plugin)
    }

    pub fn uninstall(&self, id: &str) -> Result<(), Error> {
        let _lock = self.lock()?;
        if !safe_id(id) {
            return Err(Error::Package);
        }
        fs::remove_dir_all(self.root.join(id))?;
        Ok(())
    }

    pub fn list(&self) -> Result<Vec<InstalledPlugin>, Error> {
        if !self.root.exists() {
            return Ok(vec![]);
        }
        let mut result = vec![];
        for entry in fs::read_dir(&self.root)? {
            let entry = entry?;
            if entry.file_type()?.is_dir()
                && let Some(id) = entry.file_name().to_str()
            {
                result.push(self.load(id)?);
            }
        }
        result.sort_by(|a, b| a.manifest.id.cmp(&b.manifest.id));
        Ok(result)
    }

    pub fn invoke(&self, id: &str, request: &[u8]) -> Result<serde_json::Value, Error> {
        self.invoke_at_revision(id, None, request)
    }

    pub fn invoke_at_revision(
        &self,
        id: &str,
        expected_revision: Option<&str>,
        request: &[u8],
    ) -> Result<serde_json::Value, Error> {
        let _lock = self.lock()?;
        let installed = self.load(id)?;
        if expected_revision.is_some_and(|r| r != installed.revision || r.is_empty()) {
            return Err(Error::Permission);
        }
        if !installed.enabled {
            return Err(Error::Permission);
        }
        let revision = self
            .root
            .join(id)
            .join(installed.manifest.version.to_string());
        let sealed_disk: SealedDiskPackage =
            serde_json::from_slice(&fs::read(revision.join("package.json"))?)
                .map_err(|_| Error::Package)?;
        let publisher: [u8; 32] = fs::read(revision.join("publisher.key"))?
            .try_into()
            .map_err(|_| Error::Package)?;
        let package = unseal_disk_package(&sealed_disk, &publisher)?;
        let verified = verify_sealed(&package, &publisher);
        drop(WipingBuffer(package.module.into_bytes()));
        let (manifest, sealed_module) = verified?;
        if manifest != installed.manifest {
            return Err(Error::Package);
        }
        let mut result = execute_sealed(&sealed_module, request)?;
        if let Some(obj) = result.as_object_mut() {
            obj.remove("confirmation_required");
        } else {
            return Err(Error::Package);
        }
        if let Some(ui_resource) = result.get("ui_resource") {
            validate_ui_resource_descriptor(ui_resource)?;
        }
        // Effects are proposals. The host must also authorize each method and resource.
        let mut pending_confirmations = Vec::new();
        let mut has_effects = false;
        if let Some(effects_val) = result.get("effects") {
            let effects = effects_val.as_array().ok_or(Error::Permission)?;
            has_effects = true;
            if effects.len() > 32 {
                return Err(Error::Permission);
            }
            let mut effect_ids = BTreeSet::new();
            for (idx, effect) in effects.iter().enumerate() {
                let effect_id = effect
                    .get("id")
                    .and_then(|v| v.as_str())
                    .ok_or(Error::Permission)?;
                if effect_id.is_empty()
                    || effect_id.len() > 128
                    || !effect_ids.insert(effect_id)
                    || !effect.get("arguments").is_some_and(|a| a.is_object())
                {
                    return Err(Error::Permission);
                }
                let capability = effect
                    .get("capability")
                    .and_then(|v| v.as_str())
                    .ok_or(Error::Permission)?;
                if !installed.grants.contains(capability) {
                    return Err(Error::Permission);
                }
                let method = effect
                    .get("method")
                    .and_then(|v| v.as_str())
                    .ok_or(Error::Permission)?;
                let (required_capability, read_only) = effect_capability(effect)?;
                if capability != required_capability {
                    return Err(Error::Permission);
                }
                let mut target_summary = serde_json::Value::Null;
                let mut credential_id_opt = serde_json::Value::Null;
                if required_capability == "network" {
                    let raw = effect
                        .pointer("/arguments/url")
                        .and_then(|v| v.as_str())
                        .ok_or(Error::Permission)?;
                    let url = url::Url::parse(raw).map_err(|_| Error::Permission)?;
                    if url.scheme() != "https"
                        || !url.username().is_empty()
                        || url.password().is_some()
                        || !manifest
                            .network_origins
                            .contains(&url.origin().ascii_serialization())
                    {
                        return Err(Error::Permission);
                    }
                    target_summary = serde_json::Value::String(raw.to_owned());
                    if let Some(cred_val) = effect.pointer("/arguments/credential_id") {
                        let cred_id = cred_val.as_str().ok_or(Error::Permission)?;
                        if !safe_id(cred_id) {
                            return Err(Error::Permission);
                        }
                        credential_id_opt = serde_json::Value::String(cred_id.to_owned());
                    }
                    if let Some(headers_val) = effect.pointer("/arguments/headers") {
                        let headers = headers_val.as_object().ok_or(Error::Permission)?;
                        for (h_name, h_val) in headers {
                            let val_str = h_val.as_str().ok_or(Error::Permission)?;
                            if val_str.contains('\r') || val_str.contains('\n') {
                                return Err(Error::Permission);
                            }
                            let lower = h_name.to_ascii_lowercase();
                            if matches!(
                                lower.as_str(),
                                "authorization"
                                    | "cookie"
                                    | "proxy-authorization"
                                    | "host"
                                    | "content-length"
                                    | "transfer-encoding"
                            ) {
                                return Err(Error::Permission);
                            }
                        }
                    }
                }
                if method == "host.call" {
                    target_summary = effect
                        .pointer("/arguments/api")
                        .cloned()
                        .unwrap_or_default();
                }
                if !read_only {
                    pending_confirmations.push(serde_json::json!({
                        "index": idx,
                        "method": method,
                        "capability": capability,
                        "read_only": false,
                        "target": target_summary,
                        "credential_id": credential_id_opt,
                    }));
                }
            }
        }
        if has_effects && let Some(obj) = result.as_object_mut() {
            obj.insert(
                "confirmation_required".to_owned(),
                serde_json::json!({
                    "required": !pending_confirmations.is_empty(),
                    "plugin_id": id,
                    "pending_effects": pending_confirmations,
                }),
            );
        }
        Ok(result)
    }
}

/// Executes a [`SealedWasmModule`] by decrypting its Wasm bytecode only for the
/// transient `wasmi::Module::new` compilation window and wiping the plaintext
/// bytecode buffer before instantiating or invoking the Wasm module. Wasmi's
/// compiled module and instance allocations remain ordinary runtime memory.
pub fn execute_sealed(
    sealed_module: &SealedWasmModule,
    request: &[u8],
) -> Result<serde_json::Value, Error> {
    if sealed_module.len() > MAX_MODULE_BYTES || request.len() > MAX_MESSAGE_BYTES {
        return Err(Error::Package);
    }
    let _permit = ExecutionPermit::acquire()?;
    let mut config = Config::default();
    config
        .consume_fuel(true)
        .enforced_limits(EnforcedLimits::strict());
    let engine = Engine::new(&config);
    let module = sealed_module.with_decrypted_bytes(|module_bytes| {
        Module::new(&engine, module_bytes).map_err(runtime_error)
    })?;
    execute_compiled_module(&engine, &module, request)
}

/// ABI: alloc(length)->pointer; invoke(pointer,length)->(length<<32 | pointer).
/// A fresh fuel/memory-limited instance runs per invocation, with no host imports.
pub fn execute(module: &[u8], request: &[u8]) -> Result<serde_json::Value, Error> {
    if module.len() > MAX_MODULE_BYTES || request.len() > MAX_MESSAGE_BYTES {
        return Err(Error::Package);
    }
    let _permit = ExecutionPermit::acquire()?;
    let mut config = Config::default();
    config
        .consume_fuel(true)
        .enforced_limits(EnforcedLimits::strict());
    let engine = Engine::new(&config);
    let module = Module::new(&engine, module).map_err(runtime_error)?;
    execute_compiled_module(&engine, &module, request)
}

fn execute_compiled_module(
    engine: &Engine,
    module: &Module,
    request: &[u8],
) -> Result<serde_json::Value, Error> {
    if module.imports().next().is_some() {
        return Err(Error::Permission);
    }
    let limits = StoreLimitsBuilder::new()
        .memory_size(32 * 1024 * 1024)
        .memories(1)
        .tables(1)
        .table_elements(4096)
        .instances(1)
        .build();
    let mut store = Store::new(engine, limits);
    store.limiter(|limits: &mut StoreLimits| limits);
    store.set_fuel(5_000_000).map_err(runtime_error)?;
    let linker = Linker::<StoreLimits>::new(engine);
    let instance = linker
        .instantiate_and_start(&mut store, module)
        .map_err(runtime_error)?;
    let memory = instance
        .get_memory(&store, "memory")
        .ok_or(Error::Package)?;
    let alloc = instance
        .get_typed_func::<i32, i32>(&store, "omni_alloc")
        .map_err(runtime_error)?;
    let invoke = instance
        .get_typed_func::<(i32, i32), i64>(&store, "omni_invoke")
        .map_err(runtime_error)?;
    let ptr = alloc
        .call(&mut store, request.len() as i32)
        .map_err(runtime_error)?;
    memory
        .write(&mut store, ptr as u32 as usize, request)
        .map_err(runtime_error)?;
    let packed = invoke
        .call(&mut store, (ptr, request.len() as i32))
        .map_err(runtime_error)? as u64;
    let len = (packed >> 32) as usize;
    if len > MAX_MESSAGE_BYTES {
        return Err(Error::Package);
    }
    let mut response = WipingBuffer(vec![0; len]);
    memory
        .read(&store, (packed as u32) as usize, &mut response.0)
        .map_err(runtime_error)?;
    let value: serde_json::Value = serde_json::from_slice(&response.0)?;
    if !value.is_object() {
        return Err(Error::Package);
    }
    Ok(value)
}
fn runtime_error(e: impl std::fmt::Display) -> Error {
    Error::Runtime(e.to_string())
}

pub fn default_package_directory(home: &Path) -> PathBuf {
    home.join(".vibe-space/plugins")
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    fn package(key: &SigningKey, version: u64) -> SignedPackage {
        let module = b"\0asm\x01\0\0\0";
        let manifest = Manifest {
            id: "test.extension".into(),
            version,
            api_version: 1,
            name: "Fixture".into(),
            license: "MIT".into(),
            module_sha256: STANDARD.encode(Sha256::digest(module)),
            capabilities: BTreeSet::from(["network".into()]),
            network_origins: BTreeSet::from(["https://example.com".into()]),
            contributions: vec![],
        };
        let text = serde_json::to_string(&manifest).unwrap();
        SignedPackage {
            signature: STANDARD.encode(key.sign(text.as_bytes()).to_bytes()),
            manifest: text,
            module: STANDARD.encode(module),
        }
    }

    #[test]
    fn unsupported_resource_capabilities_are_rejected() {
        let key = SigningKey::from_bytes(&[42; 32]);
        for capability in ["filesystem", "vault_read"] {
            let mut value = package(&key, 1);
            value.manifest = value
                .manifest
                .replace("\"network\"", &format!("\"{capability}\""));
            value.signature = STANDARD.encode(key.sign(value.manifest.as_bytes()).to_bytes());
            assert!(matches!(
                verify(&value, &key.verifying_key().to_bytes()),
                Err(Error::Package)
            ));
        }
    }

    #[test]
    fn legacy_manifests_cannot_receive_unsupported_grants() {
        let directory = tempfile::tempdir().unwrap();
        let store = PackageStore::new(directory.path());
        let key = SigningKey::from_bytes(&[42; 32]);
        store
            .install(&package(&key, 1), &key.verifying_key().to_bytes())
            .unwrap();
        let mut installed = store.load("test.extension").unwrap();
        for capability in ["filesystem", "vault_read"] {
            installed.manifest.capabilities.insert(capability.into());
            store.save(&installed).unwrap();
            assert!(matches!(
                store.enable("test.extension", BTreeSet::from([capability.into()])),
                Err(Error::Permission)
            ));
        }
    }

    #[test]
    fn signed_installation_upgrade_revocation_and_removal() {
        let directory = tempfile::tempdir().unwrap();
        let store = PackageStore::new(directory.path());
        let key = SigningKey::from_bytes(&[42; 32]);
        let publisher = key.verifying_key().to_bytes();
        store.install(&package(&key, 1), &publisher).unwrap();
        assert!(!store.load("test.extension").unwrap().enabled);
        assert!(matches!(
            store.invoke("test.extension", b"{}"),
            Err(Error::Permission)
        ));
        assert!(
            store
                .enable("test.extension", BTreeSet::from(["vault_read".into()]))
                .is_err()
        );
        store
            .enable("test.extension", BTreeSet::from(["network".into()]))
            .unwrap();
        let other = SigningKey::from_bytes(&[43; 32]);
        assert!(
            store
                .install(&package(&other, 2), &other.verifying_key().to_bytes())
                .is_err()
        );
        store.install(&package(&key, 2), &publisher).unwrap();
        let updated = store.load("test.extension").unwrap();
        assert!(!updated.enabled && updated.grants.is_empty());
        assert!(store.install(&package(&key, 1), &publisher).is_err());
        store.uninstall("test.extension").unwrap();
        assert!(store.list().unwrap().is_empty());
    }

    #[test]
    fn tampered_manifest_and_module_are_rejected() {
        let key = SigningKey::from_bytes(&[7; 32]);
        let mut value = package(&key, 1);
        value.manifest = value.manifest.replace("Fixture", "Changed");
        assert!(verify(&value, &key.verifying_key().to_bytes()).is_err());
        let mut value = package(&key, 1);
        value.module = STANDARD.encode(b"\0asm\x01\0\0\0extra");
        assert!(verify(&value, &key.verifying_key().to_bytes()).is_err());
    }
    #[test]
    fn wasm_has_no_ambient_io_and_is_fuel_bounded() {
        let import = br#"(module (import "wasi_snapshot_preview1" "fd_write" (func)))"#;
        assert!(matches!(execute(import, b"{}"), Err(Error::Permission)));
        let endless = br#"(module (memory (export "memory") 1)
            (func (export "omni_alloc") (param i32) (result i32) i32.const 0)
            (func (export "omni_invoke") (param i32 i32) (result i64)
                (loop $forever br $forever) i64.const 0))"#;
        assert!(matches!(execute(endless, b"{}"), Err(Error::Runtime(_))));
    }
    #[test]
    fn validates_output_memory_and_runs_downloaded_code() {
        let wasm =
            br#"(module (memory (export "memory") 1) (data (i32.const 32) "{\"view\":\"hello\"}")
            (func (export "omni_alloc") (param i32) (result i32) i32.const 1024)
            (func (export "omni_invoke") (param i32 i32) (result i64) i64.const 68719476768))"#;
        assert_eq!(execute(wasm, b"{}").unwrap()["view"], "hello");
    }

    #[test]
    fn sealed_wasm_module_masks_bytecode_in_ram_and_detects_share_tampering() {
        let key = SigningKey::from_bytes(&[19; 32]);
        let pkg = package(&key, 1);
        let (_, mut sealed) = verify_sealed(&pkg, &key.verifying_key().to_bytes()).unwrap();
        assert!(!sealed.is_empty());
        assert_ne!(
            sealed.masked_share(),
            b"\0asm\x01\0\0\0",
            "sealed Wasm module share must not expose raw \\0asm header in RAM"
        );
        sealed
            .with_decrypted_bytes(|plain| {
                assert_eq!(plain, b"\0asm\x01\0\0\0");
                Ok(())
            })
            .unwrap();

        // Corrupting a single bit of the masked share must be caught by SHA-256 verification.
        sealed.masked[0] ^= 0x01;
        assert!(matches!(
            sealed.with_decrypted_bytes(|_| Ok(())),
            Err(Error::Package)
        ));
    }

    #[test]
    fn sealed_module_remains_usable_after_callback_unwind() {
        let sealed = SealedWasmModule::seal(b"\0asm\x01\0\0\0".to_vec(), b"unwind");
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = sealed.with_decrypted_bytes::<()>(|_| panic!("callback failed"));
        }));
        assert!(result.is_err());
        sealed
            .with_decrypted_bytes(|bytes| {
                assert_eq!(bytes, b"\0asm\x01\0\0\0");
                Ok(())
            })
            .unwrap();
    }

    #[test]
    fn sealed_disk_package_hides_wasm_header_and_rejects_unsealed_disk_files() {
        let directory = tempfile::tempdir().unwrap();
        let store = PackageStore::new(directory.path());
        let key = SigningKey::from_bytes(&[51; 32]);
        let publisher = key.verifying_key().to_bytes();
        let pkg = package(&key, 1);
        store.install(&pkg, &publisher).unwrap();

        let disk_path = directory.path().join("test.extension/1/package.json");
        let on_disk_text = fs::read_to_string(&disk_path).unwrap();
        assert!(
            !on_disk_text.contains("\"module\""),
            "installed package.json must not contain unsealed module field"
        );
        assert!(
            !on_disk_text.contains("AGFzbQ"),
            "installed package.json must not expose Base64 \\0asm header on disk"
        );
        assert!(
            !PLUGIN_POLICY_VM
                .data_ciphertext
                .windows(b"terminal_write".len())
                .any(|w| w == b"terminal_write"),
            "PLUGIN_POLICY_VM ciphertext must not expose plaintext capability names"
        );

        // Overwriting package.json with an unsealed SignedPackage must be rejected
        // by both load() and invoke(), requiring re-installation.
        fs::write(&disk_path, serde_json::to_vec(&pkg).unwrap()).unwrap();
        assert!(matches!(store.load("test.extension"), Err(Error::Package)));
        assert!(matches!(
            store.invoke("test.extension", b"{}"),
            Err(Error::Package)
        ));
    }

    fn package_with_json_payload(
        key: &SigningKey,
        version: u64,
        capabilities: &[&str],
        json_payload: &str,
    ) -> SignedPackage {
        let len = json_payload.len() as u64;
        let packed = (len << 32) | 32_u64;
        let escaped = json_payload.replace('\\', "\\\\").replace('"', "\\\"");
        let wat = format!(
            r#"(module (memory (export "memory") 1) (data (i32.const 32) "{escaped}")
            (func (export "omni_alloc") (param i32) (result i32) i32.const 32768)
            (func (export "omni_invoke") (param i32 i32) (result i64) i64.const {packed}))"#
        );
        let engine = Engine::default();
        let _ = Module::new(&engine, wat.as_bytes()).unwrap();
        // Use the WAT text or binary via wasmi::wat if supported, or compile via wat::parse_str:
        // Note: wasmi with "wat" feature parses WAT directly in Module::new, while verify() checks \0asm header.
        // Build a minimal valid binary Wasm module with the exact data segment:
        let mut wasm = Vec::from(&b"\0asm\x01\0\0\0"[..]);
        // Type section (id=1): 2 func types: (i32)->i32 and (i32,i32)->i64
        wasm.extend_from_slice(&[
            0x01, 0x0c, 0x02, 0x60, 0x01, 0x7f, 0x01, 0x7f, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7e,
        ]);
        // Function section (id=3): 2 functions (type 0, type 1)
        wasm.extend_from_slice(&[0x03, 0x03, 0x02, 0x00, 0x01]);
        // Memory section (id=5): 1 memory (min 1 page)
        wasm.extend_from_slice(&[0x05, 0x03, 0x01, 0x00, 0x01]);
        // Export section (id=7): "memory" (mem 0), "omni_alloc" (func 0), "omni_invoke" (func 1)
        let exports: &[u8] = &[
            0x03, 0x06, b'm', b'e', b'm', b'o', b'r', b'y', 0x02, 0x00, 0x0a, b'o', b'm', b'n',
            b'i', b'_', b'a', b'l', b'l', b'o', b'c', 0x00, 0x00, 0x0b, b'o', b'm', b'n', b'i',
            b'_', b'i', b'n', b'v', b'o', b'k', b'e', 0x00, 0x01,
        ];
        wasm.push(0x07);
        wasm.push(exports.len() as u8);
        wasm.extend_from_slice(exports);
        // Code section (id=10):
        // func 0: [] i32.const 32768 (0x41 0x80 0x80 0x02) end (0x0b)
        // func 1: [] i64.const <packed> end
        let mut i64_leb = Vec::new();
        let mut val = packed as i64;
        loop {
            let mut byte = (val & 0x7f) as u8;
            val >>= 7;
            if (val == 0 && (byte & 0x40) == 0) || (val == -1 && (byte & 0x40) != 0) {
                i64_leb.push(byte);
                break;
            }
            byte |= 0x80;
            i64_leb.push(byte);
        }
        let mut func1_body = vec![0x00, 0x42];
        func1_body.extend_from_slice(&i64_leb);
        func1_body.push(0x0b);
        let mut code_sec = vec![0x02, 0x06, 0x00, 0x41, 0x80, 0x80, 0x02, 0x0b];
        code_sec.push(func1_body.len() as u8);
        code_sec.extend_from_slice(&func1_body);
        wasm.push(0x0a);
        wasm.push(code_sec.len() as u8);
        wasm.extend_from_slice(&code_sec);
        // Data section (id=11): 1 segment at mem 0, offset i32.const 32 (0x41, 0x20, 0x0b), bytes
        let payload_bytes = json_payload.as_bytes();
        let mut data_sec = vec![0x01, 0x00, 0x41, 0x20, 0x0b];
        let mut p_len = payload_bytes.len();
        loop {
            let mut b = (p_len & 0x7f) as u8;
            p_len >>= 7;
            if p_len != 0 {
                b |= 0x80;
            }
            data_sec.push(b);
            if p_len == 0 {
                break;
            }
        }
        data_sec.extend_from_slice(payload_bytes);
        wasm.push(0x0b);
        let mut sec_len = data_sec.len();
        let mut sec_len_leb = Vec::new();
        loop {
            let mut b = (sec_len & 0x7f) as u8;
            sec_len >>= 7;
            if sec_len != 0 {
                b |= 0x80;
            }
            sec_len_leb.push(b);
            if sec_len == 0 {
                break;
            }
        }
        wasm.extend_from_slice(&sec_len_leb);
        wasm.extend_from_slice(&data_sec);

        let manifest = Manifest {
            id: "test.extension".into(),
            version,
            api_version: 1,
            name: "Fixture".into(),
            license: "MIT".into(),
            module_sha256: STANDARD.encode(Sha256::digest(&wasm)),
            capabilities: capabilities.iter().map(|s| (*s).to_owned()).collect(),
            network_origins: BTreeSet::from(["https://example.com".into()]),
            contributions: vec![],
        };
        let text = serde_json::to_string(&manifest).unwrap();
        SignedPackage {
            signature: STANDARD.encode(key.sign(text.as_bytes()).to_bytes()),
            manifest: text,
            module: STANDARD.encode(&wasm),
        }
    }

    #[test]
    fn invoke_returns_structured_confirmation_required_and_validates_opaque_credentials_and_ui_resources()
     {
        let directory = tempfile::tempdir().unwrap();
        let store = PackageStore::new(directory.path());
        let key = SigningKey::from_bytes(&[63; 32]);
        let publisher = key.verifying_key().to_bytes();

        let output_json = r#"{"view":"ok","ui_resource":{"uri":"ui://omniterm/work-result.html","mime_type":"text/html;profile=mcp-app"},"effects":[{"id":"request","capability":"network","method":"network.fetch","arguments":{"url":"https://example.com/api","credential_id":"vault-cred-1"}}]}"#;
        let pkg = package_with_json_payload(&key, 1, &["network", "terminal_read"], output_json);
        store.install(&pkg, &publisher).unwrap();
        store
            .enable(
                "test.extension",
                BTreeSet::from(["network".into(), "terminal_read".into()]),
            )
            .unwrap();

        // 1. Unconfirmed invocation returns structured confirmation_required proposal for the Flutter UI.
        let unconfirmed = store.invoke("test.extension", b"{}").unwrap();
        assert_eq!(unconfirmed["confirmation_required"]["required"], true);
        assert_eq!(
            unconfirmed["confirmation_required"]["plugin_id"],
            "test.extension"
        );
        let pending = unconfirmed["confirmation_required"]["pending_effects"]
            .as_array()
            .unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0]["method"], "network.fetch");
        assert_eq!(pending[0]["credential_id"], "vault-cred-1");
        assert_eq!(pending[0]["read_only"], false);

        // 2. A caller flag never authorizes effects or bypasses host review.
        let confirmed = store
            .invoke("test.extension", br#"{"confirmed_effects":true}"#)
            .unwrap();
        assert_eq!(confirmed["confirmation_required"]["required"], true);
        assert!(
            !confirmed["confirmation_required"]["pending_effects"]
                .as_array()
                .unwrap()
                .is_empty()
        );

        // 3. Inline Authorization header or unsafe ui_resource URI must be rejected with Error::Permission.
        let bad_header_json = r#"{"effects":[{"id":"request","capability":"network","method":"network.fetch","arguments":{"url":"https://example.com/api","headers":{"Authorization":"Bearer secret"}}}]}"#;
        let bad_pkg = package_with_json_payload(&key, 2, &["network"], bad_header_json);
        store.install(&bad_pkg, &publisher).unwrap();
        store
            .enable("test.extension", BTreeSet::from(["network".into()]))
            .unwrap();
        assert!(matches!(
            store.invoke("test.extension", b"{}"),
            Err(Error::Permission)
        ));
    }

    fn shannon_entropy_bits_per_byte(bytes: &[u8]) -> f64 {
        if bytes.is_empty() {
            return 0.0;
        }
        let mut counts = [0usize; 256];
        for &b in bytes {
            counts[usize::from(b)] += 1;
        }
        let total = bytes.len() as f64;
        let mut entropy = 0.0_f64;
        for &count in &counts {
            if count > 0 {
                let p = (count as f64) / total;
                entropy -= p * p.log2();
            }
        }
        entropy
    }

    fn percentile_ns(sorted_ns: &[u128], permille: usize) -> u128 {
        assert!(!sorted_ns.is_empty());
        let idx = ((sorted_ns.len() - 1) * permille) / 1000;
        sorted_ns[idx]
    }

    #[test]
    fn deep_forensics_entropy_bitflip_and_latency_verification() {
        use std::hint::black_box;
        use std::time::Instant;

        // Verify domain separation & canary coupling in PLUGIN_POLICY_VM
        assert!(PLUGIN_POLICY_VM.execute(0, b"network", 0).is_ok());
        assert_eq!(classify_plugin_policy_segment(0, b"MIT"), None);
        assert_eq!(classify_plugin_policy_segment(1, b"network"), None);
        assert_eq!(classify_plugin_policy_segment(2, b"MIT"), None);
        assert_ne!(plugin_policy_seal_token(), [0_u8; 8]);

        let directory = tempfile::tempdir().unwrap();
        let store = PackageStore::new(directory.path());
        let key = SigningKey::from_bytes(&[0x5A; 32]);
        let publisher = key.verifying_key().to_bytes();

        // Build a realistic multi-kilobyte (~4.2 KiB) Wasm module with structured output, UI resource, and effects
        let mut body_records = String::with_capacity(4096);
        for i in 0..48 {
            if i > 0 {
                body_records.push(',');
            }
            body_records.push_str(&format!(
                r#"{{"seq":{i},"host":"node-{i:03}.prod.example.com","status":"healthy","latency_ms":{}}}"#,
                (i * 17) % 95 + 5
            ));
        }
        let realistic_json = format!(
            r#"{{"view":"cluster-summary","records":[{body_records}],"ui_resource":{{"uri":"ui://omniterm/cluster-topology.html","mime_type":"text/html;profile=mcp-app"}},"effects":[{{"id":"request","capability":"network","method":"network.fetch","arguments":{{"url":"https://example.com/api/v1/nodes","credential_id":"vault-node-reader"}}}}]}}"#
        );
        let pkg =
            package_with_json_payload(&key, 1, &["network", "terminal_read"], &realistic_json);
        let raw_wasm_plaintext = STANDARD.decode(&pkg.module).unwrap();
        assert!(
            raw_wasm_plaintext.len() >= 4096,
            "expected multi-kilobyte Wasm payload, got {} bytes",
            raw_wasm_plaintext.len()
        );

        store.install(&pkg, &publisher).unwrap();
        store
            .enable(
                "test.extension",
                BTreeSet::from(["network".into(), "terminal_read".into()]),
            )
            .unwrap();

        // (a) Raw on-disk forensics
        let disk_path = directory.path().join("test.extension/1/package.json");
        let raw_disk_bytes = fs::read(&disk_path).unwrap();
        assert!(
            !raw_disk_bytes.windows(4).any(|w| w == b"\0asm"),
            "raw \\0asm magic bytes must never appear in on-disk package.json"
        );
        assert!(
            !raw_disk_bytes.windows(6).any(|w| w == b"AGFzbQ"),
            "Base64 \\0asm prefix AGFzbQ must never appear in on-disk package.json"
        );

        let orig_disk: SealedDiskPackage = serde_json::from_slice(&raw_disk_bytes).unwrap();
        let sealed_ciphertext = STANDARD.decode(&orig_disk.sealed_module).unwrap();
        assert_eq!(sealed_ciphertext.len(), raw_wasm_plaintext.len());

        let plaintext_entropy = shannon_entropy_bits_per_byte(&raw_wasm_plaintext);
        let ciphertext_entropy = shannon_entropy_bits_per_byte(&sealed_ciphertext);
        println!(
            "[FORENSICS][ENTROPY] Wasm payload size: {} bytes | Plaintext H = {:.6} bits/byte | Sealed Ciphertext H = {:.6} bits/byte",
            sealed_ciphertext.len(),
            plaintext_entropy,
            ciphertext_entropy
        );
        assert!(
            ciphertext_entropy > 7.5,
            "sealed_module Shannon entropy must exceed 7.5 bits/byte, got {ciphertext_entropy:.6}"
        );

        // (b) Bit-flip avalanche oracle
        // 1. sealed_module bit flips (256 single-bit flips evenly strided across the multi-KiB ciphertext)
        let mut module_flips_total = 0usize;
        let mut module_flips_rejected = 0usize;
        for i in 0..256 {
            let byte_idx = (i * 31) % sealed_ciphertext.len();
            let bit_mask = 1_u8 << (i & 7);
            let mut mutated_ct = sealed_ciphertext.clone();
            mutated_ct[byte_idx] ^= bit_mask;
            let mut mutated_disk = orig_disk.clone();
            mutated_disk.sealed_module = STANDARD.encode(&mutated_ct);
            module_flips_total += 1;
            if matches!(
                unseal_disk_package(&mutated_disk, &publisher),
                Err(Error::Package)
            ) {
                module_flips_rejected += 1;
            }
            if i < 16 {
                fs::write(&disk_path, serde_json::to_vec(&mutated_disk).unwrap()).unwrap();
                assert!(matches!(
                    store.invoke("test.extension", b"{}"),
                    Err(Error::Package)
                ));
            }
        }
        assert_eq!(module_flips_rejected, module_flips_total);

        // 2. seal_tag bit flips (all 256 bits of the 32-byte SHA-256 tag)
        let orig_tag = STANDARD.decode(&orig_disk.seal_tag).unwrap();
        assert_eq!(orig_tag.len(), 32);
        let mut tag_flips_total = 0usize;
        let mut tag_flips_rejected = 0usize;
        for bit in 0..256 {
            let mut mutated_tag = orig_tag.clone();
            mutated_tag[bit / 8] ^= 1_u8 << (bit % 8);
            let mut mutated_disk = orig_disk.clone();
            mutated_disk.seal_tag = STANDARD.encode(&mutated_tag);
            tag_flips_total += 1;
            if matches!(
                unseal_disk_package(&mutated_disk, &publisher),
                Err(Error::Package)
            ) {
                tag_flips_rejected += 1;
            }
            if bit < 16 {
                fs::write(&disk_path, serde_json::to_vec(&mutated_disk).unwrap()).unwrap();
                assert!(matches!(
                    store.invoke("test.extension", b"{}"),
                    Err(Error::Package)
                ));
            }
        }
        assert_eq!(tag_flips_rejected, tag_flips_total);

        // 3. manifest bit flips (128 single-bit flips across ASCII characters of manifest JSON)
        let orig_manifest_bytes = orig_disk.manifest.as_bytes().to_vec();
        let mut manifest_flips_total = 0usize;
        let mut manifest_flips_rejected = 0usize;
        for i in 0..128 {
            let byte_idx = i % orig_manifest_bytes.len();
            let mut mutated_manifest = orig_manifest_bytes.clone();
            // Flip bit 0 so ASCII stays valid UTF-8 (0..=127)
            mutated_manifest[byte_idx] ^= 0x01;
            let mut mutated_disk = orig_disk.clone();
            mutated_disk.manifest = String::from_utf8(mutated_manifest).unwrap();
            manifest_flips_total += 1;
            if matches!(
                unseal_disk_package(&mutated_disk, &publisher),
                Err(Error::Package)
            ) {
                manifest_flips_rejected += 1;
            }
            if i < 16 {
                fs::write(&disk_path, serde_json::to_vec(&mutated_disk).unwrap()).unwrap();
                assert!(matches!(
                    store.invoke("test.extension", b"{}"),
                    Err(Error::Package)
                ));
            }
        }
        assert_eq!(manifest_flips_rejected, manifest_flips_total);

        // 4. signature bit flips (all 512 bits of the 64-byte Ed25519 signature)
        let orig_sig = STANDARD.decode(&orig_disk.signature).unwrap();
        assert_eq!(orig_sig.len(), 64);
        let mut sig_flips_total = 0usize;
        let mut sig_flips_rejected = 0usize;
        for bit in 0..512 {
            let mut mutated_sig = orig_sig.clone();
            mutated_sig[bit / 8] ^= 1_u8 << (bit % 8);
            let mut mutated_disk = orig_disk.clone();
            mutated_disk.signature = STANDARD.encode(&mutated_sig);
            sig_flips_total += 1;
            if matches!(
                unseal_disk_package(&mutated_disk, &publisher),
                Err(Error::Package)
            ) {
                sig_flips_rejected += 1;
            }
            if bit < 16 {
                fs::write(&disk_path, serde_json::to_vec(&mutated_disk).unwrap()).unwrap();
                assert!(matches!(
                    store.invoke("test.extension", b"{}"),
                    Err(Error::Package)
                ));
            }
        }
        assert_eq!(sig_flips_rejected, sig_flips_total);

        // 5. publisher key bit flips (all 256 bits of the 32-byte publisher key)
        let mut pub_flips_total = 0usize;
        let mut pub_flips_rejected = 0usize;
        for bit in 0..256 {
            let mut mutated_pub = publisher;
            mutated_pub[bit / 8] ^= 1_u8 << (bit % 8);
            pub_flips_total += 1;
            if matches!(
                unseal_disk_package(&orig_disk, &mutated_pub),
                Err(Error::Package)
            ) {
                pub_flips_rejected += 1;
            }
        }
        assert_eq!(pub_flips_rejected, pub_flips_total);

        // Restore valid on-disk package.json before latency benchmarks
        fs::write(&disk_path, &raw_disk_bytes).unwrap();
        println!(
            "[FORENSICS][BITFLIP] sealed_module: {module_flips_rejected}/{module_flips_total} | seal_tag: {tag_flips_rejected}/{tag_flips_total} | manifest: {manifest_flips_rejected}/{manifest_flips_total} | signature: {sig_flips_rejected}/{sig_flips_total} | publisher_key: {pub_flips_rejected}/{pub_flips_total} (100.0% Err(Error::Package))"
        );

        // (c) Latency distribution microbenchmark
        const FAST_ITERS: usize = 10_000;
        const INVOKE_ITERS: usize = 200;

        let mut vm_cap_ns = Vec::with_capacity(FAST_ITERS);
        for _ in 0..FAST_ITERS {
            let t0 = Instant::now();
            let out = PLUGIN_POLICY_VM
                .execute(black_box(0), black_box(b"network"), black_box(0))
                .unwrap();
            black_box(out);
            vm_cap_ns.push(t0.elapsed().as_nanos());
        }
        vm_cap_ns.sort_unstable();

        let mut vm_method_ns = Vec::with_capacity(FAST_ITERS);
        for _ in 0..FAST_ITERS {
            let t0 = Instant::now();
            let out = PLUGIN_POLICY_VM
                .execute(black_box(2), black_box(b"network.fetch"), black_box(0))
                .unwrap();
            black_box(out);
            vm_method_ns.push(t0.elapsed().as_nanos());
        }
        vm_method_ns.sort_unstable();

        let mut unseal_ns = Vec::with_capacity(FAST_ITERS);
        for _ in 0..FAST_ITERS {
            let t0 = Instant::now();
            let out = unseal_disk_package(black_box(&orig_disk), black_box(&publisher)).unwrap();
            black_box(out);
            unseal_ns.push(t0.elapsed().as_nanos());
        }
        unseal_ns.sort_unstable();

        let mut invoke_unconfirmed_ns = Vec::with_capacity(INVOKE_ITERS);
        for _ in 0..INVOKE_ITERS {
            let t0 = Instant::now();
            let out = store
                .invoke(black_box("test.extension"), black_box(b"{}"))
                .unwrap();
            assert_eq!(out["confirmation_required"]["required"], true);
            black_box(out);
            invoke_unconfirmed_ns.push(t0.elapsed().as_nanos());
        }
        invoke_unconfirmed_ns.sort_unstable();

        let mut invoke_confirmed_ns = Vec::with_capacity(INVOKE_ITERS);
        for _ in 0..INVOKE_ITERS {
            let t0 = Instant::now();
            let out = store
                .invoke(
                    black_box("test.extension"),
                    black_box(br#"{"confirmed_effects":true}"#),
                )
                .unwrap();
            assert_eq!(out["confirmation_required"]["required"], true);
            black_box(out);
            invoke_confirmed_ns.push(t0.elapsed().as_nanos());
        }
        invoke_confirmed_ns.sort_unstable();

        for (label, samples) in [
            ("PLUGIN_POLICY_VM.execute(0, \"network\", 0)", &vm_cap_ns),
            (
                "PLUGIN_POLICY_VM.execute(2, \"network.fetch\", 0)",
                &vm_method_ns,
            ),
            ("unseal_disk_package (4.3 KiB Wasm)", &unseal_ns),
            ("PackageStore::invoke (unconfirmed)", &invoke_unconfirmed_ns),
            (
                "PackageStore::invoke (confirmed_effects: true)",
                &invoke_confirmed_ns,
            ),
        ] {
            let p50 = percentile_ns(samples, 500);
            let p95 = percentile_ns(samples, 950);
            let p99 = percentile_ns(samples, 990);
            let p999 = percentile_ns(samples, 999);
            println!(
                "[FORENSICS][LATENCY] {:<48} | n={:<5} | p50={:>8} ns ({:>7.2} us) | p95={:>8} ns ({:>7.2} us) | p99={:>8} ns ({:>7.2} us) | p99.9={:>8} ns ({:>7.2} us)",
                label,
                samples.len(),
                p50,
                (p50 as f64) / 1000.0,
                p95,
                (p95 as f64) / 1000.0,
                p99,
                (p99 as f64) / 1000.0,
                p999,
                (p999 as f64) / 1000.0,
            );
        }

        // Verify anti-spoofing of confirmation_required and rejection of non-array effects
        let spoofed_pkg = package_with_json_payload(
            &key,
            2,
            &["network"],
            r#"{"view":"ok","confirmation_required":{"required":false,"pending_effects":[]}}"#,
        );
        store.install(&spoofed_pkg, &publisher).unwrap();
        store
            .enable("test.extension", BTreeSet::from(["network".into()]))
            .unwrap();
        let cleaned = store.invoke("test.extension", b"{}").unwrap();
        assert!(
            cleaned.get("confirmation_required").is_none(),
            "plugin-supplied confirmation_required must be stripped when no effects are present"
        );

        let non_array_effects_pkg = package_with_json_payload(
            &key,
            3,
            &["network"],
            r#"{"view":"ok","effects":{"capability":"network","method":"network.fetch"}}"#,
        );
        store.install(&non_array_effects_pkg, &publisher).unwrap();
        store
            .enable("test.extension", BTreeSet::from(["network".into()]))
            .unwrap();
        assert!(matches!(
            store.invoke("test.extension", b"{}"),
            Err(Error::Permission)
        ));
    }
    #[test]
    fn activation_revision_never_revives_old_invocations() {
        let dir = tempfile::tempdir().unwrap();
        let store = PackageStore::new(dir.path());
        let key = SigningKey::from_bytes(&[38; 32]);
        let pkg = package_with_json_payload(
            &key,
            1,
            &["api:leapterm.ui"],
            r#"{"view":{"type":"text","text":"hello"}}"#,
        );
        store
            .install(&pkg, &key.verifying_key().to_bytes())
            .unwrap();
        let installed = store.load("test.extension").unwrap().revision;
        let grants = BTreeSet::from(["api:leapterm.ui".to_owned()]);
        store.enable("test.extension", grants.clone()).unwrap();
        let first = store.load("test.extension").unwrap().revision;
        assert_ne!(installed, first);
        assert!(
            store
                .invoke_at_revision("test.extension", Some(&first), b"{}")
                .is_ok()
        );
        store.disable("test.extension").unwrap();
        store.enable("test.extension", grants).unwrap();
        let second = store.load("test.extension").unwrap().revision;
        assert_ne!(first, second);
        assert!(matches!(
            store.invoke_at_revision("test.extension", Some(&first), b"{}"),
            Err(Error::Permission)
        ));
        assert!(
            store
                .invoke_at_revision("test.extension", Some(&second), b"{}")
                .is_ok()
        );
    }

    #[test]
    fn compile_and_instance_resources_are_bounded() {
        let oversized_type = format!("(module (func (param {})))", "i32 ".repeat(33));
        assert!(matches!(
            execute(oversized_type.as_bytes(), b"{}"),
            Err(Error::Runtime(_))
        ));
        let tiny_function_flood = format!("(module {})", "(func)".repeat(10001));
        assert!(matches!(
            execute(tiny_function_flood.as_bytes(), b"{}"),
            Err(Error::Runtime(_))
        ));
        let huge_memory = br#"(module (memory (export "memory") 513))"#;
        assert!(execute(huge_memory, b"{}").is_err());
    }

    #[test]
    fn host_api_capabilities_are_exact_and_manifest_slots_validated() {
        for cap in ["api:", "api:a..b", "api:a/b", "filesystem", "vault_read"] {
            assert!(!is_supported_capability(cap));
        }
        assert_eq!(effect_capability(&serde_json::json!({"method":"host.call","capability":"api:leapterm.ui","arguments":{"api":"leapterm.ui","version":1,"input":{}}})).unwrap(),("api:leapterm.ui".to_owned(),false));
        assert!(effect_capability(&serde_json::json!({"method":"host.call","capability":"terminal_read","arguments":{"api":"leapterm.ui"}})).is_err());
        let key = SigningKey::from_bytes(&[39; 32]);
        for (field, value) in [
            ("network_origins", serde_json::json!(["http://localhost"])),
            (
                "contributions",
                serde_json::json!([{"id":"x","slot":"raw_html","title":"X","command":"open"}]),
            ),
        ] {
            let mut pkg = package(&key, 1);
            let mut manifest: serde_json::Value = serde_json::from_str(&pkg.manifest).unwrap();
            manifest[field] = value;
            pkg.manifest = manifest.to_string();
            pkg.signature = STANDARD.encode(key.sign(pkg.manifest.as_bytes()).to_bytes());
            assert!(verify(&pkg, &key.verifying_key().to_bytes()).is_err());
        }
    }
}
