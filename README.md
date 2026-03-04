# Butler v2.0.0 — Documentation

> Memory management module for Roblox Luau.  
> Supersedes Maid, Trove, and Janitor with a far richer feature set drawn from systems languages, reactive programming, and modern resource management proposals.

---

## Philosophy & Influences

Butler doesn't just copy Maid and Trove — it draws from battle-tested patterns across the software world:

| Source | Pattern Borrowed | Butler Feature |
|---|---|---|
| **Rust** | `Drop` trait — resources tied to scope lifetime | `butler:Guard()`, LIFO cleanup order |
| **Rust** | `defer!` macro via `scopeguard` crate | `butler:Defer()` |
| **C++** | `std::unique_ptr` with custom deleter, `SCOPE_EXIT` | `butler:Guard()`, `butler:Defer()` |
| **RxJS** | `takeUntil` operator | `butler:Until()` |
| **RxJS** | `CompositeDisposable` / `Subscription` groups | `butler:Batch()` |
| **RxJS** | `finalize()` teardown observer | `butler:OnClean()` |
| **TC39** | Explicit Resource Management (`using` / `Symbol.dispose`) | `butler:Wrap()` |
| **Go** | `defer` statement | `butler:Defer()` |
| **Angular** | `DestroyRef` lifecycle abstraction | `butler:LinkToInstance()` |

---

## Why Not Just Use Maid/Trove/Janitor?

| Problem | Butler Solution |
|---|---|
| No named/keyed task slots — you can't replace one task | `:Set("name", obj)` replaces and cleans the old one |
| `:Destroy()` twice throws an error | Double-destroy is a safe no-op |
| One bad task crashes the whole cleanup chain | All errors are caught, warned, and execution continues |
| No `:Once()` that is also safe if the butler dies first | `:Once()` auto-disconnects OR cleans if butler dies first |
| No sub-scoping / parent-child relationship | `:Scope()` creates a child butler with inherited lifetime |
| Tweens: `:Destroy()` doesn't stop a playing animation | `:Tween()` calls `:Cancel()` before `:Destroy()` |
| No way to replace a running animation/connection atomically | `:Set("slot", newTween)` cancels the old one first |
| No interval helpers — must wire RunService manually | `:Every(interval, fn)` tracked loop, auto-cancelled |
| No thread management — manual `task.spawn` leaks | `:Task()`, `:Delay()` — threads tracked and cancelled |
| No way to couple a resource to its custom teardown inline | `:Guard(value, fn)` — Rust-style Drop at acquisition site |
| No SCOPE_EXIT / defer for side effects | `:Defer(fn)` — Go-style deferred cleanup |
| No batch-add | `:Batch({...})` — add many items at once |
| No teardown hooks | `:OnClean(fn)` — fires after every Clean/Destroy |
| No way to early-dispose one item while keeping tracking | `:Wrap(obj)` returns a disposable proxy |
| No fluent/builder chaining | `:AddChain()` returns self |
| No debug visibility into what's tracked | `:Snapshot()`, `Butler.setDebug(true)` |

---

## Installation

Drop `Butler.rbxm` into **ReplicatedStorage** (or ServerScriptService) and require it:

```lua
local Butler = require(ReplicatedStorage.Butler)
```

---

## Quick Start

```lua
local Butler = require(ReplicatedStorage.Butler)
local RunService = game:GetService("RunService")

local butler = Butler.new()

-- Track a connection
butler:Connect(RunService.Heartbeat, function(dt) doWork(dt) end)

-- Named slot — auto-replaces on next call
butler:Set("character", character)

-- Child scope
local charScope = butler:Scope()
charScope:Add(someModel)

-- Auto-destroy when player leaves
butler:LinkToInstance(player)

-- Done:
butler:Destroy()
```

---

## Full API Reference

### `Butler.new()` → `Butler`
Creates a new Butler.

### `Butler.setDebug(enabled: boolean)`
Global toggle. When `true`, Butler prints each task as it is cleaned with elapsed time. Use during development to find leaks.

---

### Core Tracking

#### `butler:Add(object, method?, label?)` → `object`
Tracks any object for cleanup. Returns the object for inline use.

| Type | Default Cleanup |
|---|---|
| `function` | `object()` |
| `RBXScriptConnection` | `object:Disconnect()` |
| `thread` | `task.cancel(object)` |
| `Instance` | `object:Destroy()` |
| Table + `Destroy` | `object:Destroy()` |
| Table + `destroy` | `object:destroy()` |
| Table + `Disconnect` | `object:Disconnect()` |
| Tween (has `Cancel`+`Play`) | `object:Cancel()` then `object:Destroy()` |
| Promise (`getStatus`+`cancel`) | `object:cancel()` if Running |
| `method` provided | `object:<method>()` |

```lua
local conn = butler:Add(signal:Connect(fn))
butler:Add(someInstance)
butler:Add(myTween, "Cancel")
butler:Add(function() print("cleaned!") end)
```

#### `butler:AddChain(object, method?)` → `butler`
Same as `:Add()` but returns `self` for builder chaining:

```lua
Butler.new()
    :AddChain(conn1)
    :AddChain(conn2)
    :AddChain(part)
    :LinkToInstance(player)
```

#### `butler:Set(name, object, method?)` → `object`
Named slot. If the slot is already occupied, the old object is cleaned first.

```lua
butler:Set("healthBar", healthBarGui)
-- Later on respawn:
butler:Set("healthBar", newHealthBarGui)  -- old one auto-destroyed
```

#### `butler:Remove(nameOrObject)`
Remove and clean a single task by name or reference:

```lua
butler:Remove("healthBar")      -- by name
butler:Remove(someConnection)   -- by reference
```

#### `butler:Has(name)` → `boolean`
Returns `true` if a named slot is occupied.

#### `butler:Count()` → `number`
Total number of currently tracked tasks.

#### `butler:IsAlive()` → `boolean`
Returns `false` after `:Destroy()` has been called.

---

### Signals

#### `butler:Connect(signal, fn)` → `RBXScriptConnection`
Shorthand for `butler:Add(signal:Connect(fn))`.

#### `butler:Once(signal, fn)` → `RBXScriptConnection`
One-shot connection. Disconnects after first fire. If the butler is destroyed first, the connection is still disconnected safely — no dangling callbacks.

#### `butler:Until(untilSignal, listenSignal, fn)` → `RBXScriptConnection`
**RxJS `takeUntil` pattern.** Connects `fn` to `listenSignal`, but permanently disconnects the moment `untilSignal` fires.

```lua
-- Update NPC AI on Heartbeat until it dies:
butler:Until(
    npc.Humanoid.Died,
    RunService.Heartbeat,
    function(dt) updateNPC(npc, dt) end
)
```

#### `butler:ConnectMany({{signal, fn}, ...})` → `{RBXScriptConnection}`
Connect multiple signal→fn pairs in one call:

```lua
butler:ConnectMany({
    { RunService.Heartbeat,   onHeartbeat },
    { player.CharacterAdded, onCharacter  },
})
```

---

### Constructing & Instances

#### `butler:Construct(class, ...)` → `object`
Create and immediately track an object:

```lua
local sig = butler:Construct(Signal)          -- calls Signal.new()
local sig = butler:Construct(Signal.new)      -- function constructor
local part = butler:Construct(Instance.new, "Part")
```

#### `butler:Clone(instance)` → `Instance`
Clone an instance and track the result.

#### `butler:AddInstance(inst, parent?)` → `Instance`
Track an instance and optionally parent it in one call:

```lua
local part = butler:AddInstance(Instance.new("Part"), workspace)
```

---

### Async / Threads

#### `butler:Task(fn)` → `thread`
Spawn a tracked `task.spawn` thread. If the butler is destroyed, the thread is cancelled. Think of it as a Rust *scoped thread* — its lifetime is bounded by the butler's.

```lua
butler:Task(function()
    while true do
        doWork()
        task.wait(0.05)
    end
end)
```

#### `butler:Delay(t, fn)` → `thread`
Schedule a call after `t` seconds. Thread is tracked and cancellable:

```lua
butler:Delay(5, function()
    print("5 seconds later — or never if butler died")
end)
```

#### `butler:Every(interval, fn)` → `thread`
Run `fn` on a fixed interval using a tracked loop. No RunService connection needed:

```lua
butler:Every(1/20, function()
    updateMinimap()
end)
```

---

### Rust / C++ Patterns

#### `butler:Guard(value, cleanupFn)` → `value`
**Rust `Drop` trait / C++ `ScopeGuard` / `unique_ptr` with custom deleter.**

Couples a resource to its cleanup function at the *acquisition site* — the core RAII principle. The cleanup function receives the value as its argument.

```lua
-- Acquisition and teardown are co-located and explicit:
local lock  = butler:Guard(acquireLock(),   function(l) l:release() end)
local sound = butler:Guard(Sound:Play(),    function(s) s:Stop() end)
local file  = butler:Guard(openFile(path),  function(f) f:close() end)
```

Unlike `:Add(obj, "Method")`, Guard accepts arbitrary teardown logic and makes the relationship between resource and destructor unambiguous.

#### `butler:Defer(fn)` → `butler`
**C++ `SCOPE_EXIT` / Go `defer` / Rust `defer!` macro.**

Queues a side-effect to run at the next `Clean()` or `Destroy()`. Explicitly communicates "this is a cleanup action, not a tracked resource":

```lua
butler:Defer(function()
    Analytics:recordSessionEnd(player)
    print("Scope exited.")
end)
```

Returns `self` for chaining.

---

### RxJS / Reactive Patterns

#### `butler:Batch({items})` → `butler`
**RxJS `CompositeDisposable` pattern.** Add multiple items at once:

```lua
butler:Batch({
    conn1,
    conn2,
    { myTween, "Cancel" },  -- {object, method} pair
    { myAudio, "Stop"   },
})
```

#### `butler:OnClean(fn)` → `butler`
**RxJS `finalize()` operator.** Registers a teardown observer that fires after every `Clean()` or `Destroy()`:

```lua
butler:OnClean(function()
    Metrics:recordCleanup(player)
    print("Cleanup complete!")
end)
```

Multiple observers can be registered; all are called in order.

#### `butler:Wrap(object)` → `DisposableHandle`
**TC39 Explicit Resource Management / `Symbol.dispose` / JavaScript `using` keyword.**

Returns a proxy that forwards all method calls to the wrapped object, but adds a `:Dispose()` method for early removal from the butler:

```lua
-- JavaScript equivalent: `using stream = openStream();`
local handle = butler:Wrap(openStream())
handle:Read(1024)   -- proxied to stream:Read(1024)
handle:Dispose()    -- removes stream from butler, cleans it early
-- If :Dispose() is never called, butler:Destroy() cleans it normally
```

---

### Roblox QoL

#### `butler:Tween(instance, tweenInfo, goals)` → `Tween`
Create, play, and track a Tween. On cleanup, `:Cancel()` is called *before* `:Destroy()` — stopping any mid-play animation. Maid, Trove, and Janitor all miss this and only call `:Destroy()`, which doesn't stop a playing tween:

```lua
local tween = butler:Tween(
    part,
    TweenInfo.new(0.5, Enum.EasingStyle.Quad),
    { CFrame = targetCFrame }
)
-- part smoothly moves. If butler:Destroy() fires, the part stops immediately.
```

#### `butler:WaitFor(inst, childName, timeout?)` → `Instance?`
A tracked `WaitForChild` wrapper. If the butler is destroyed while waiting, the coroutine is cancelled — no orphaned yields:

```lua
local gui = butler:WaitFor(player.PlayerGui, "MainGui", 10)
if gui then
    setupGui(gui)
end
```

---

### Scoping & Linking

#### `butler:Scope()` → `Butler`
Create a child butler whose lifetime is tied to the parent. Inspired by Rust's `std::thread::scope`:

```lua
local playerButler = Butler.new()

local function onCharacterAdded(char)
    -- Create a new scope each respawn
    local charScope = playerButler:Scope()
    charScope:Add(char)
    charScope:Once(char.Humanoid.Died, function()
        print("died")
    end)
end

player.CharacterAdded:Connect(onCharacterAdded)
-- When playerButler:Destroy() is called, all charScopes are also destroyed
```

#### `butler:LinkToInstance(instance, allowReAdd?)` → `RBXScriptConnection`
Auto-destroy the butler when a Roblox instance is destroyed:

```lua
butler:LinkToInstance(player)           -- Destroy() on player leave
butler:LinkToInstance(character, true)  -- Clean() only (reuse the butler)
```

---

### Lifecycle

#### `butler:Clean()`
Clean all tasks and fire OnClean observers, but keep the butler alive for reuse. Cleanup order: named tasks → anonymous tasks (LIFO) → OnClean observers.

#### `butler:Destroy()`
Clean and permanently invalidate. Calling `:Destroy()` a second time is a safe no-op.

#### `butler:Snapshot()` → `{[key]: string}`
Returns a table of all tracked tasks keyed by their index or name. Use during development to inspect what's currently tracked:

```lua
local snap = butler:Snapshot()
for k, v in pairs(snap) do
    print(k, "→", v)
end
-- 1 → RBXScriptConnection
-- 2 → thread
-- healthConn → RBXScriptConnection
-- character → Instance
```

---

## Common Patterns

### Per-Player Setup

```lua
local Butler = require(ReplicatedStorage.Butler)

local playerButlers: { [Player]: typeof(Butler.new()) } = {}

game.Players.PlayerAdded:Connect(function(player)
    local butler = Butler.new()
    playerButlers[player] = butler
    butler:LinkToInstance(player)  -- auto-destroys on leave

    butler:OnClean(function()
        print(player.Name, "left, all cleaned up")
    end)

    butler:Connect(player.CharacterAdded, function(char)
        local scope = butler:Scope()
        scope:Add(char)
        scope:Until(
            char.Humanoid.Died,
            game:GetService("RunService").Heartbeat,
            function(dt) updateCharacter(char, dt) end
        )
    end)
end)
```

### OOP Class with Butler

```lua
local MySystem = {}
MySystem.__index = MySystem

function MySystem.new(player)
    local self = setmetatable({}, MySystem)
    self._butler = Butler.new()
    self._butler:LinkToInstance(player)
    self._butler:OnClean(function()
        print("MySystem cleaned up")
    end)
    return self
end

function MySystem:Destroy()
    self._butler:Destroy()
end
```

### Animation State Machine

```lua
-- Cleanly swap animations using named slots + Tween cleanup
local function playAnimation(butler, track, info, goals)
    -- Old tween is Cancel()'d and Destroy()'d before new one plays
    butler:Set("activeTween", butler:Tween(character.HumanoidRootPart, info, goals))
end
```

### Scoped Debug Session

```lua
Butler.setDebug(true)

local butler = Butler.new()
butler:Defer(function()
    print("Total tasks cleaned:", taskCount)
end)

Butler.setDebug(false)  -- turn off for production
```

### Batch Connection

```lua
butler:Batch({
    RunService.Heartbeat:Connect(onHeartbeat),
    RunService.RenderStepped:Connect(onRender),
    { myTween, "Cancel" },
    { mySound, "Stop"   },
})
```

---

## Cleanup Order (LIFO — same as Rust)

Butler cleans anonymous tasks in **Last In, First Out** order, mirroring how Rust drops local variables and how C++ destroys stack objects. This means the most recently added resource is cleaned first, which is the safest default:

```lua
butler:Add(A)  -- cleaned 3rd
butler:Add(B)  -- cleaned 2nd
butler:Add(C)  -- cleaned 1st ← last added, first cleaned
```

Named tasks are cleaned before anonymous tasks, in arbitrary order.

---

*Butler v2.0.0*
