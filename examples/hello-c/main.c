#include "vibe_space.h"
VIBE_INVOKE {
  (void)pointer; (void)length;
  static const char output[] = "{\"view\":{\"type\":\"card\",\"children\":[{\"type\":\"heading\",\"text\":\"Hello from C\"},{\"type\":\"text\",\"text\":\"No WASI, no imports. The same module runs in browsers and native hosts.\"}]}}";
  return vibe_result(output, sizeof(output)-1);
}
