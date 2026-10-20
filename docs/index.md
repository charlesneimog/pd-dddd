---
hide:
 - navigation
 - menu
---

# dddd — Getting Started, Examples, and API Reference

**A beginner-friendly guide to structured data in Pure Data using Lua**

This guide is based on the supplied `dddd.lua` implementation and its `dddd.ex1.pd_lua` example. The installation workflow described here uses **xlab**, as requested by the project author. The code examples and API descriptions correspond to that implementation; they should be reviewed if the module is updated.

## 1. What is dddd?

Pure Data (Pd) normally sends simple messages made of numbers and symbols. These messages are useful, but are not a convenient way to represent nested musical data, such as multiple chords in a progression or a rhythm tree.

**dddd** lets Pd-Lua objects exchange structured values backed by Lua tables. For example, a chord can be represented as:

```lua
{60, 64, 67}
```

A series of three chords can be represented as a *nested* table:

```lua
{
    {60, 64, 67},
    {62, 65, 69},
    {67, 71, 74}
}
```

In Lua, `{}` creates a table. A table can contain values or other tables. These nested tables are the main data structure used by `dddd`.

A `dddd` message does **not** place the entire nested table in the Pd patch cord. Instead, it briefly registers the table and sends a small reference token. The receiving Pd-Lua object immediately resolves that token and obtains its own copy of the nested table.

**Important distinction:** `dddd` is a Lua library for people writing Pd objects; it is not a Pd object named `[dddd]` that you create in a patch.

## 2. Install xlab using Deken

The project distributes `dddd` through the **xlab** library. For the installation workflow described in this guide, use the following steps:

1. Open **Pure Data**.
2. Choose **Tools → Find Externals** to open Deken, Pd's package manager.
3. Search for **`xlab`**.
4. Select the appropriate **xlab** package and install it.
5. Close and reopen Pd if the newly installed library is not detected immediately.
6. Create a new Pd patch and add this object:

```text
[declare -lib xlab]
```

This tells Pd to load `xlab` for the patch. The `dddd` Lua module is then expected to be available through the `xlab` installation.

**Environment note:** The project targets Pure Data 0.57 and PlugData 0.9.4. This guide does not establish compatibility with older releases.

**If Lua objects do not load:** Pd-Lua (`pdlua`) must also be available and loaded. Some environments include it; in Pd vanilla, it may need separate installation using Deken. Where needed, add `[declare -lib pdlua]` or configure `pdlua` to load at startup. This is a prerequisite for creating objects from `.pd_lua` files, not a second installation of `dddd`.

## 3. Create a Pd-Lua object

A Pd-Lua object is a text file with the extension **`.pd_lua`**. The file contains Lua code that registers a Pd class. If the file is named `dddd.demo.pd_lua`, the class must also be called `dddd.demo`.

Create a file called **`dddd.demo.pd_lua`** and save it in the **same folder as your Pd patch**. Paste in the following code:

```lua
-- Load dddd from xlab.
local dddd = require("dddd")

-- Register the Pd object class.
local demo = pd.Class:new():register("dddd.demo")

-- Configure one inlet and one outlet.
function demo:initialize()
    self.inlets = 1
    self.outlets = 1
    return true
end

-- When the object receives a bang, send three chords.
function demo:in_1_bang()
    local chords = {
        {60, 64, 67},
        {62, 65, 69},
        {67, 71, 74}
    }

    local data = dddd:new_from_table(self, chords)
    data:output(1)
end

-- When the object receives a dddd message, read it.
function demo:in_1_dddd(atoms)
    local data = dddd:new_from_atoms(self, atoms)
    local chords = data:get_table()
    pd.post("dddd.demo received: " .. data:to_string(chords))
end
```

**You do not create `[pd_lua]` as the name of your custom object.** Pd-Lua supplies the loader for files ending in `.pd_lua`; your own object in this example is `[dddd.demo]`.

### Understand the main lines

| Lua code | Meaning |
| --- | --- |
| `local dddd = require("dddd")` | Loads the Lua module distributed with xlab. |
| `pd.Class:new():register("dddd.demo")` | Tells Pd the name of this Lua object. |
| `initialize()` | Declares the object's inlets and outlets. |
| `in_1_bang()` | Runs when inlet 1 receives a `bang`. |
| `dddd:new_from_table(self, chords)` | Wraps an existing Lua table in a `dddd` instance. |
| `data:output(1)` | Sends the value out of outlet 1. |
| `in_1_dddd(atoms)` | Runs when inlet 1 receives a `dddd` message. |
| `dddd:new_from_atoms(self, atoms)` | Resolves the incoming reference and copies the data. |
| `data:get_table()` | Gets the underlying Lua table. |
| `data:to_string(chords)` | Creates a readable nested-list representation. |

## 4. Test the object in Pd

1. Open a patch in the **same folder** as `dddd.demo.pd_lua`.
2. Add `[declare -lib xlab]`.
3. Create a `[bang]` message/button.
4. Create **two** `[dddd.demo]` objects, one below the other.
5. Connect the bang to the first object, and connect the first object's outlet to the second object's inlet.
6. Open the Pd console and click the bang.

```text
[declare -lib xlab]

[bang]
  |
[dddd.demo]    <- sender
  |
[dddd.demo]    <- receiver
```

The second instance receives the `dddd` message and displays a line similar to:

```text
dddd.demo received: ((60 64 67) (62 65 69) (67 71 74))
```

The first instance creates a nested Lua table and sends it. The second instance reconstructs the nested table, then displays it. The content is preserved even though Pd's patch cord carries only a temporary reference.

**Try changing the notes:** edit `{60, 64, 67}` in the Lua file, save it, and reload/recreate the Lua object in Pd to apply the change. Reopening the patch is the simplest reliable beginner workflow.

## 5. How dddd data travels through Pd

This is the message-transfer process implemented in the supplied source:

1. **Create:** A sending object constructs a `dddd` instance from a Lua table.
2. **Register:** `data:output(1)` assigns the value a temporary random identifier of 12 hexadecimal characters, enclosed in angle brackets.
3. **Send:** Pd receives a message with the selector `dddd` and that identifier as its atom.
4. **Receive:** A connected Pd-Lua object handles the message in `in_1_dddd(atoms)`.
5. **Copy:** `dddd:new_from_atoms(self, atoms)` looks up the temporary identifier and deep-copies the nested table.
6. **Clean up:** The sending object's registry entry is cleared once the synchronous Pd outlet call returns.

The temporary identifier is not a permanent address or an on-disk serialization format. **Do not save it for later, send it through a delayed message, or expect it to work after the originating output call finishes.** The receiving object must resolve it during the immediate message flow.

### Why copies matter

If one outlet connects to two receiver objects, each receiver obtains an independent nested table. If one receiver modifies its copy, the other receiver's copy is not modified. This is useful for composing different transformations of a shared musical structure.

Creating a `dddd` from a Lua table with `new_from_table` does not copy that original table immediately; the copying occurs when a receiver resolves an emitted reference. Calling `get_table()` also returns the table stored inside that instance, not a fresh copy.

## 6. The most useful API methods

The following methods come from the provided `dddd.lua` implementation.

### `dddd:new_from_table(self, table)`

Wrap a Lua table as a `dddd` instance. `self` is usually `self` inside the Lua object's method.

```lua
local data = dddd:new_from_table(self, {60, 64, 67})
```

### `data:output(outlet_number)`

Send the `dddd` value through a Pd outlet. Outlet numbers start at 1.

```lua
data:output(1)
```

### `dddd:new_from_atoms(self, atoms)`

Receive a `dddd` message inside an `in_1_dddd` or equivalent method.

```lua
function demo:in_1_dddd(atoms)
    local data = dddd:new_from_atoms(self, atoms)
end
```

The first atom must be the temporary ID emitted by a connected `dddd` sender.

### `data:get_table()`

Retrieve the Lua value stored by the current instance.

```lua
local notes = data:get_table()
local first_chord = notes[1]
local first_pitch = first_chord[1]
```

### `data:to_string(value)`

Convert a sequential Lua table to a readable nested-list string.

```lua
pd.post(data:to_string(data:get_table()))
```

`to_string` defaults to parenthesized lists when no other delimiter style has been initialized. It is useful for debugging, but it is not a general-purpose serialization of all Lua types.

### `data:get_table_depth()` and `data:get_depth(value)`

Find the nesting depth. A simple list has depth 1; a list of lists has depth 2.

```lua
local depth = data:get_table_depth()
pd.post("Depth: " .. depth)
```

### `data:set_type(name)` and `data:get_type()`

Attach or read an optional type label on a `dddd` instance.

```lua
data:set_type("chords")
pd.post(data:get_type())
```

**Important:** the provided send/receive path copies the table but does **not** propagate this type label to the receiver. Use it only as local instance metadata unless you implement type information explicitly in your data structure.

## 7. Additional API methods

These methods exist in the supplied source but are less important for a first object.

| Method | Function | Important note |
| --- | --- | --- |
| `dddd:new(self, atoms)` | Creates an instance and converts incoming Pd atoms using `table_from_atoms`. | For common examples, prefer `new_from_table` or `new_from_atoms`. |
| `dddd:new_from_id(self, id)` | Resolves a temporary message ID and copies its table. | Use only during synchronous message handling while the ID exists. |
| `data:lisplist_to_table(text)` | Parses one fully enclosed parenthesized or bracketed list. | Returns `nil` if no valid outer list is found. |
| `data:table_from_atoms(atoms)` | Converts a Pd atom list into a Lua table, inferring bracket style. | The implementation is designed around whitespace-delimited sequential lists. |
| `data:check_brackets(text)` | Checks whether bracket or parenthesis syntax is used. | Mixed `[]` and `()` styles raise an error. |
| `data:print()` | Prints the current value to Pd's console. | In the supplied implementation, fresh values made with `new_from_table` might not have a delimiter style set; `to_string` plus `pd.post` is more reliable for this case. |
| `data:assert_type(name)` | Checks the current instance's type label. | Its error text compares the requested and stored labels; take care when using it as a validation message. |
| `data:get_dddd_from_id(self, id)` | Older alternative for resolving an ID. | The supplied implementation should be reviewed before relying on it; `new_from_atoms` is the recommended receiving method. |

Methods with leading underscores (`_random_string`, `_parse_list`, `_deep_copy_table`) are implementation helpers, not part of the beginner workflow.

## 8. Reading and writing nested-list syntax

The supplied code can parse lists written with matching parentheses:

```text
(1 (2 3) four)
```

Or with matching square brackets:

```text
[1 [2 3] four]
```

Both represent the Lua table:

```lua
{1, {2, 3}, "four"}
```

This parser recognizes whitespace-separated tokens. Tokens accepted by Lua's `tonumber` become numbers; other tokens become strings.

**Limitations:**

- Do not mix `()` and `[]` in one expression.
- The parser does not implement quoting or escaping. Do not use the textual syntax for strings containing spaces or list delimiter characters.
- Table-to-string conversion uses sequential integer-indexed elements. Associative tables and arbitrary Lua objects are not faithfully represented by the text format.
- Deep copying focuses on nested Lua tables. Non-table values are kept as-is.

For most custom music applications, **creating nested tables directly in Lua** is simpler and more reliable than constructing or parsing textual lists.

## 9. Use dddd in a musical transformation

Once the receiving object has the table, you can manipulate it using ordinary Lua. For example, transpose the first chord by two semitones:

```lua
function demo:in_1_dddd(atoms)
    local data = dddd:new_from_atoms(self, atoms)
    local chords = data:get_table()

    for i, pitch in ipairs(chords[1]) do
        chords[1][i] = pitch + 2
    end

    pd.post("Transposed: " .. data:to_string(chords))
end
```

In this version, the receiving object modifies its own copy. The original sender's table is unaffected. To forward the modified result to another object, use `data:output(1)` inside the receiving method; make sure the patch does not accidentally route the forwarded data back into itself.

## 10. Troubleshooting

**Pd cannot create `[dddd.demo]`**  
Check that the file is named `dddd.demo.pd_lua`, its class registration is exactly `"dddd.demo"`, the file is on Pd's search path (the patch folder is a good starting point), and Pd-Lua is loaded. Try restarting Pd after installation.

**Lua reports `module 'dddd' not found`**  
Check that **xlab** is installed and that `[declare -lib xlab]` has loaded it. The module must be in a location accessible to Lua's module loader. If your xlab version does not ship the module, check that the installed package and project documentation correspond to the same release.

**An incoming `dddd` ID cannot be found**  
Do not store or delay the temporary ID. Pass the message directly from the sending object's outlet to a `dddd`-aware receiving object.

**The receiving object prints only an ID such as `<a1b2...>`**  
A standard Pd `[print]` object sees the transport message, not the nested table. Connect a Lua receiver implementing `in_1_dddd(atoms)` and print `data:to_string(data:get_table())` instead.

**Nothing appears in the console**  
Make sure a bang reaches the first instance, both instances are connected, and the Pd console is open.

**A mixed-bracket error appears**  
Use parentheses only or square brackets only within one textual list; do not combine them.

## 11. Scope and limitations

- `dddd` is intended for structured **message-rate** data, not processing audio samples in the DSP signal path.
- The registry used to pass references is shared among cooperating objects within the same Lua runtime. In the project distribution model, **xlab** provides the single integrated implementation required by the framework.
- The reference lifetime is synchronous: receivers must reconstruct values before the sender's outlet call returns.
- Every receiver makes a recursive table copy. This favors predictable Pd-like value semantics but has performance and memory overhead proportional to the size of the nested structure.
- Semantic type labels are local metadata in the supplied implementation; they are not automatically transmitted along with the data.
- Array-style nested tables are the safest common data form for this implementation.

## 12. Further resources

Source code: `https://github.com/charlesneimog/pd-dddd`  
Project documentation: `https://github.com/charlesneimog/pd-dddd/wiki`  
Pd-Lua: `https://github.com/agraef/pd-lua`  
Deken user guide: `https://deken.readthedocs.io/latest/plugin/`

**Files provided with this guide:**

- `dddd.demo.pd_lua` — the complete Lua example
- `dddd-demo.pd` — a Pd patch that connects two instances

---

*Implementation note: The source supplied for this documentation may differ from the current files in the public GitHub repository. The guide describes the behavior actually visible in that supplied `dddd.lua`.*
