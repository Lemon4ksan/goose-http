// Generation-checked handles: a slot in a table of the owner's, and the
// generation the slot had when the handle was made. Reusing a slot advances
// its generation, so a handle kept past its slot's reuse no longer matches
// and is refused rather than taken for the slot's next occupant. The timer
// table uses them, and so does the HTTP layer for the exchanges that wait.
// Nothing here knows HTTP: this file imports nothing of the package's HTTP
// side, so that it can move to a package of its own unchanged.
namespace http;

struct Handle { slot: i32 = -1, gen: u32 = 0 }

// A handle as a 64-bit number, for a key that crosses threads or the
// kernel: the generation above, the slot below.
fn key_of(h: Handle) -> u64 { ((h.gen as u64) << 32) | (h.slot as! u32) }

fn handle_of(key: u64) -> Handle { Handle { slot: (key & 0xFFFFFFFF) as! u32 as! i32, gen: (key >> 32) as! u32 } }

// The generation after gen, never 0, so that a zero Handle matches no slot.
fn next_gen(gen: u32) -> u32 { if gen == 0xFFFFFFFF { 1 } else { gen + 1 } }
