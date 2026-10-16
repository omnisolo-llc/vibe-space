//! Language-neutral JSON ABI types. See the hello-rust example for exports.
//! Import-free guest ABI. Build with `--target wasm32-unknown-unknown`.
pub use serde_json::{Value, json};

/// Export a handler `fn(Value) -> Value`. A fresh instance handles each call;
/// keep persistent state in the returned JSON, or propose namespaced storage.
#[macro_export]
macro_rules! export_guest {
    ($handler:path) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn omni_alloc(length: u32) -> u32 {
            assert!(length <= 1_048_576);
            let input = vec![0u8; length as usize].into_boxed_slice();
            Box::into_raw(input) as *mut u8 as u32
        }
        /// The host supplies the exact pointer and length returned by omni_alloc.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn omni_invoke(pointer: u32, length: u32) -> u64 {
            assert!(length <= 1_048_576);
            let input = unsafe {
                Box::from_raw(std::ptr::slice_from_raw_parts_mut(
                    pointer as *mut u8,
                    length as usize,
                ))
            };
            let request: $crate::Value =
                $crate::serde_json::from_slice(&input).expect("invalid invocation JSON");
            let response = $handler(request);
            let output = $crate::serde_json::to_vec(&response)
                .expect("invalid result JSON")
                .into_boxed_slice();
            assert!(output.len() <= 1_048_576);
            let length = output.len() as u64;
            let pointer = Box::into_raw(output) as *mut u8 as u32;
            (length << 32) | u64::from(pointer)
        }
    };
}
#[doc(hidden)]
pub use serde_json;
