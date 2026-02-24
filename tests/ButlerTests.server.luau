--[[
╔══════════════════════════════════════════════════════════════════════════════╗
║                     B U T L E R   T E S T   S U I T E                        ║
║                          Run inside Roblox Studio                            ║
║                  Paste into a Script in ServerScriptService                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

  WHAT THIS FILE DOES:
    Runs 20 numbered test cases, one per API feature.
    Each test prints clear PASS / FAIL output to the Studio Output window.
    After all tests, a summary shows totals.

  HOW TO RUN:
    1. Place Butler.rbxm in ReplicatedStorage named "Butler"
    2. Place THIS file as a Script in ServerScriptService
    3. Press Play (server-side execution)
    4. Check the Output window

  OUTPUT FORMAT:
    [TEST 01] Add + auto-detect cleanup ..................... PASS
    [TEST 02] ...

  NOTE: Tests that involve signals / timing use short task.wait() pauses
  so the scheduler can fire events between setup and assertion.
--]]

-- ─── Setup ───────────────────────────────────────────────────────────────────

local Butler = require(game:GetService("ReplicatedStorage"):WaitForChild("Butler"))

-- Turn Butler's internal debug log ON for the whole test run so you can see
-- exactly what it's cleaning inside each test case.
Butler.setDebug(true)

-- ─── Test harness ────────────────────────────────────────────────────────────

local PASS  = "PASS"
local FAIL  = "FAIL"
local total = 0
local passed = 0
local failed = 0

-- Pretty separator printed before every test
local function _header(n: number, name: string)
	total += 1
	print(("\n%s"):format(string.rep("─", 72)))
	print(("[TEST %02d] %s"):format(n, name))
	print(string.rep("─", 72))
end

-- Call at end of each test with a boolean result
local function _result(n: number, name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		print(("[TEST %02d] %-50s %s"):format(n, name, PASS))
	else
		failed += 1
		warn(("[TEST %02d] %-50s %s%s"):format(
			n, name, FAIL,
			detail and (" — " .. detail) or ""
		))
	end
end

-- Small helper: make a fake "service" table with Destroy tracking
local function makeDestroyable(label: string)
	local t = { destroyed = false, label = label }
	function t:Destroy()
		self.destroyed = true
		print(("  [mock] %s:Destroy() called"):format(self.label))
	end
	return t
end

local function makeDisconnectable(label: string)
	local t = { disconnected = false, label = label }
	function t:Disconnect()
		self.disconnected = true
		print(("  [mock] %s:Disconnect() called"):format(self.label))
	end
	return t
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 01 — butler:Add() auto-detects cleanup for functions, connections,
--           instances, destroyables, disconnectables
-- ═══════════════════════════════════════════════════════════════════════════════
_header(1, "Add() — auto-detect cleanup for all types")

do
	local butler = Butler.new()

	-- Track function
	local fnCalled = false
	butler:Add(function() fnCalled = true end)

	-- Track destroyable table
	local obj = makeDestroyable("Destroyable-A")
	butler:Add(obj)

	-- Track disconnectable table
	local disc = makeDisconnectable("Disconnectable-A")
	butler:Add(disc)

	-- Track a real RBXScriptConnection
	local connFired = false
	local conn = butler:Add(
		workspace.ChildAdded:Connect(function() connFired = true end)
	)

	-- Track a thread
	local threadAlive = true
	butler:Add(task.spawn(function()
		while true do task.wait(0.1) end
		threadAlive = false -- never reached naturally
	end))

	print("  Butler before destroy:", tostring(butler))
	butler:Destroy()
	print("  Butler after destroy:", tostring(butler))

	local ok = fnCalled and obj.destroyed and disc.disconnected
	_result(1, "Add() auto-detect cleanup", ok,
		not fnCalled and "function not called"
		or not obj.destroyed and "Destroy() not called"
		or not disc.disconnected and "Disconnect() not called"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 02 — butler:Add(obj, customMethod) calls the named method
-- ═══════════════════════════════════════════════════════════════════════════════
_header(2, "Add() — custom cleanup method string")

do
	local butler = Butler.new()

	local tween = { cancelled = false, destroyed = false }
	function tween:Cancel() self.cancelled = true  print("  [mock] Tween:Cancel()") end
	function tween:Destroy() self.destroyed = true print("  [mock] Tween:Destroy()") end
	function tween:Play() end

	-- Add with "Cancel" as cleanup method
	butler:Add(tween, "Cancel")

	butler:Destroy()

	_result(2, "Add() custom method called", tween.cancelled and not tween.destroyed,
		not tween.cancelled and "Cancel was not called"
		or tween.destroyed and "Destroy was wrongly called"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 03 — butler:AddChain() returns self for fluent chaining
-- ═══════════════════════════════════════════════════════════════════════════════
_header(3, "AddChain() — fluent builder pattern")

do
	local destroyedA = false
	local destroyedB = false
	local destroyedC = false

	local butler = Butler.new()
		:AddChain(function() destroyedA = true end)
		:AddChain(function() destroyedB = true end)
		:AddChain(function() destroyedC = true end)

	print("  Count after chain:", butler:Count())
	butler:Destroy()

	_result(3, "AddChain() chains and all tasks cleaned",
		destroyedA and destroyedB and destroyedC,
		"One or more chained tasks not cleaned"
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 04 — butler:Set() replaces previous task in named slot
-- ═══════════════════════════════════════════════════════════════════════════════
_header(4, "Set() — named slot replacement")

do
	local butler = Butler.new()

	local first = makeDestroyable("First")
	local second = makeDestroyable("Second")

	butler:Set("slot", first)
	print("  Has 'slot' after first Set:", butler:Has("slot"))

	-- This should auto-clean `first` before inserting `second`
	butler:Set("slot", second)
	print("  first.destroyed after replacement:", first.destroyed)

	-- Only `second` should be cleaned on Destroy
	butler:Destroy()

	_result(4, "Set() replaces and auto-cleans old task",
		first.destroyed and second.destroyed,
		not first.destroyed and "Old task was NOT cleaned on replacement"
		or not second.destroyed and "New task was NOT cleaned on Destroy"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 05 — butler:Has() and butler:Remove() by name and by reference
-- ═══════════════════════════════════════════════════════════════════════════════
_header(5, "Has() + Remove() by name and reference")

do
	local butler = Butler.new()

	local namedObj = makeDestroyable("Named")
	local anonObj  = makeDestroyable("Anonymous")

	butler:Set("named", namedObj)
	butler:Add(anonObj)

	print("  Has('named') before Remove:", butler:Has("named"))

	-- Remove named
	butler:Remove("named")
	print("  Has('named') after Remove:", butler:Has("named"))
	print("  namedObj.destroyed:", namedObj.destroyed)

	-- Remove anonymous by reference
	butler:Remove(anonObj)
	print("  anonObj.destroyed:", anonObj.destroyed)
	print("  Count after both removes:", butler:Count())

	local ok = namedObj.destroyed and anonObj.destroyed
		and not butler:Has("named")
		and butler:Count() == 0

	_result(5, "Has() + Remove() named and by-reference",
		ok,
		not namedObj.destroyed and "named was not destroyed"
		or not anonObj.destroyed and "anon was not destroyed"
		or butler:Count() ~= 0 and ("Count not 0, got " .. butler:Count())
		or nil
	)

	butler:Destroy()
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 06 — butler:Count() and butler:IsAlive()
-- ═══════════════════════════════════════════════════════════════════════════════
_header(6, "Count() + IsAlive()")

do
	local butler = Butler.new()

	print("  IsAlive() before Destroy:", butler:IsAlive())
	print("  Count() empty:", butler:Count())

	butler:Add(function() end)
	butler:Add(function() end)
	butler:Set("x", makeDestroyable("X"))

	print("  Count() with 3 tasks:", butler:Count())

	butler:Destroy()
	print("  IsAlive() after Destroy:", butler:IsAlive())
	print("  Count() after Destroy:", butler:Count())

	_result(6, "Count() and IsAlive() correct",
		butler:Count() == 0 and not butler:IsAlive(),
		"Count or IsAlive returned wrong value"
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 07 — butler:Connect() tracks connection + disconnects on Destroy
-- ═══════════════════════════════════════════════════════════════════════════════
_header(7, "Connect() — tracked signal connection")

do
	local butler = Butler.new()
	local fireCount = 0

	-- BindableEvent as a controllable signal
	local event = Instance.new("BindableEvent")
	butler:Connect(event.Event, function()
		fireCount += 1
		print("  signal fired, count:", fireCount)
	end)

	event:Fire() -- should increment
	task.wait()  -- let scheduler dispatch

	butler:Destroy()

	event:Fire() -- should NOT increment — connection was disconnected
	task.wait()

	event:Destroy()

	_result(7, "Connect() fires once then disconnects on Destroy",
		fireCount == 1,
		("fireCount expected 1, got %d"):format(fireCount)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 08 — butler:Once() — fires once, auto-removes, safe if butler dies first
-- ═══════════════════════════════════════════════════════════════════════════════
_header(8, "Once() — one-shot auto-disconnect")

do
	local butler = Butler.new()
	local fireCount = 0

	local event = Instance.new("BindableEvent")
	butler:Once(event.Event, function()
		fireCount += 1
		print("  Once() fired, count:", fireCount)
	end)

	event:Fire() -- fires, auto-disconnects
	task.wait()
	event:Fire() -- should NOT fire again
	task.wait()
	event:Fire()
	task.wait()

	print("  fireCount after 3 fires:", fireCount)
	print("  Butler count after Once fired:", butler:Count())

	butler:Destroy()
	event:Destroy()

	_result(8, "Once() fires exactly once",
		fireCount == 1,
		("fireCount expected 1, got %d"):format(fireCount)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 09 — butler:Once() safe if butler destroyed before signal fires
-- ═══════════════════════════════════════════════════════════════════════════════
_header(9, "Once() — safe destroy before signal fires")

do
	local butler = Butler.new()
	local fired = false

	local event = Instance.new("BindableEvent")
	butler:Once(event.Event, function()
		fired = true
		print("  SHOULD NOT PRINT — butler was destroyed first")
	end)

	-- Destroy butler before the event fires
	butler:Destroy()
	print("  Butler destroyed. Firing signal now...")

	event:Fire()
	task.wait()

	event:Destroy()

	_result(9, "Once() safely disconnected when butler destroyed first",
		not fired,
		"Callback fired even after butler was destroyed"
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 10 — butler:Until() — takeUntil: stops listening when trigger fires
-- ═══════════════════════════════════════════════════════════════════════════════
_header(10, "Until() — takeUntil pattern (RxJS)")

do
	local butler = Butler.new()
	local listenCount = 0

	local listenEvent = Instance.new("BindableEvent")
	local untilEvent  = Instance.new("BindableEvent")

	butler:Until(untilEvent.Event, listenEvent.Event, function()
		listenCount += 1
		print("  Until listen fired, count:", listenCount)
	end)

	listenEvent:Fire() ; task.wait() -- count = 1
	listenEvent:Fire() ; task.wait() -- count = 2
	untilEvent:Fire()  ; task.wait() -- triggers stop
	listenEvent:Fire() ; task.wait() -- should NOT increment
	listenEvent:Fire() ; task.wait() -- should NOT increment

	print("  listenCount after until fired:", listenCount)
	print("  Tasks remaining after until:", butler:Count())

	butler:Destroy()
	listenEvent:Destroy()
	untilEvent:Destroy()

	_result(10, "Until() stops listening after trigger fires",
		listenCount == 2,
		("listenCount expected 2, got %d"):format(listenCount)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 11 — butler:ConnectMany() — batch signal connections
-- ═══════════════════════════════════════════════════════════════════════════════
_header(11, "ConnectMany() — batch connect multiple signals")

do
	local butler = Butler.new()
	local fires = { a = 0, b = 0, c = 0 }

	local evA = Instance.new("BindableEvent")
	local evB = Instance.new("BindableEvent")
	local evC = Instance.new("BindableEvent")

	local conns = butler:ConnectMany({
		{ evA.Event, function() fires.a += 1 ; print("  evA fired") end },
		{ evB.Event, function() fires.b += 1 ; print("  evB fired") end },
		{ evC.Event, function() fires.c += 1 ; print("  evC fired") end },
	})

	print("  Connections returned:", #conns)

	evA:Fire() ; evB:Fire() ; evC:Fire() ; task.wait()

	butler:Destroy()

	evA:Fire() ; evB:Fire() ; evC:Fire() ; task.wait() -- should NOT fire

	evA:Destroy() ; evB:Destroy() ; evC:Destroy()

	_result(11, "ConnectMany() connects and tracks all signals",
		#conns == 3 and fires.a == 1 and fires.b == 1 and fires.c == 1,
		("fires: a=%d b=%d c=%d (all should be 1)"):format(fires.a, fires.b, fires.c)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 12 — butler:Construct() + butler:Clone() + butler:AddInstance()
-- ═══════════════════════════════════════════════════════════════════════════════
_header(12, "Construct() + Clone() + AddInstance()")

do
	local butler = Butler.new()

	-- Construct from class table
	local MyClass = {}
	MyClass.__index = MyClass
	MyClass.destroyed = false
	function MyClass.new() return setmetatable({ destroyed = false }, MyClass) end
	function MyClass:Destroy() self.destroyed = true ; print("  MyClass:Destroy()") end

	local instance = butler:Construct(MyClass)
	print("  Constructed object type:", typeof(instance))

	-- Clone a real instance
	local template = Instance.new("Part")
	template.Name = "Template"
	local cloned = butler:Clone(template)
	print("  Cloned instance:", cloned.Name, "— parent before AddInstance:", tostring(cloned.Parent))

	-- AddInstance with parenting
	local part = butler:AddInstance(Instance.new("Part"), workspace)
	part.Name = "ButlerTestPart"
	print("  AddInstance parent:", part.Parent.Name)

	print("  Count with 3 constructed items:", butler:Count())
	butler:Destroy()

	_result(12, "Construct/Clone/AddInstance tracked + cleaned",
		instance.destroyed and not cloned.Parent and not part.Parent,
		not instance.destroyed and "MyClass not destroyed"
		or cloned.Parent and "Clone still parented"
		or part.Parent and "Part still parented"
		or nil
	)

	template:Destroy()
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 13 — butler:Task() + butler:Delay() + butler:Every()
-- ═══════════════════════════════════════════════════════════════════════════════
_header(13, "Task() + Delay() + Every() — thread tracking")

do
	local butler = Butler.new()
	local taskRan   = false
	local delayRan  = false
	local everyCount = 0

	-- Task: runs immediately
	butler:Task(function()
		taskRan = true
		print("  Task() coroutine started")
		task.wait(10) -- long wait — will be cancelled
		print("  Task() SHOULD NOT REACH HERE")
	end)

	-- Delay: fires after 0.1s
	butler:Delay(0.1, function()
		delayRan = true
		print("  Delay() fired")
	end)

	-- Every: fires every 0.05s
	butler:Every(0.05, function()
		everyCount += 1
		print("  Every() tick:", everyCount)
	end)

	task.wait(0.3) -- let delay fire and every tick ~5 times

	print("  taskRan:", taskRan)
	print("  delayRan:", delayRan)
	print("  everyCount before destroy:", everyCount)

	local countBefore = everyCount
	butler:Destroy() -- cancels the every loop thread

	task.wait(0.3) -- every should NOT have incremented after destroy
	print("  everyCount after destroy:", everyCount)

	_result(13, "Task/Delay/Every threads tracked and cancelled",
		taskRan and delayRan and everyCount >= 3 and everyCount == countBefore,
		not taskRan and "Task() did not run"
		or not delayRan and "Delay() did not fire"
		or everyCount < 3 and ("Every ticked only " .. everyCount .. " times")
		or everyCount ~= countBefore and "Every() continued after Destroy()"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 14 — butler:Guard() — Rust Drop / C++ ScopeGuard pattern
-- ═══════════════════════════════════════════════════════════════════════════════
_header(14, "Guard() — Rust Drop / C++ ScopeGuard")

do
	local butler = Butler.new()

	-- Simulate acquiring a resource with a custom teardown
	local lockReleased = false
	local lock = { name = "MyLock" }

	local guardedLock = butler:Guard(lock, function(l)
		lockReleased = true
		print(("  Guard: releasing lock '%s'"):format(l.name))
	end)

	-- Guard returns the value for inline use
	print("  guardedLock == lock:", guardedLock == lock)
	print("  lockReleased before Destroy:", lockReleased)

	butler:Destroy()
	print("  lockReleased after Destroy:", lockReleased)

	_result(14, "Guard() calls cleanup fn with value on Destroy",
		guardedLock == lock and lockReleased,
		not (guardedLock == lock) and "Guard did not return the original value"
		or not lockReleased and "Guard cleanup fn was not called"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 15 — butler:Defer() — Go defer / C++ SCOPE_EXIT
-- ═══════════════════════════════════════════════════════════════════════════════
_header(15, "Defer() — Go defer / C++ SCOPE_EXIT")

do
	local butler = Butler.new()
	local order = {}

	-- Defer is LIFO with anonymous tasks — last deferred, first run
	butler:Defer(function()
		table.insert(order, "deferred-1")
		print("  Defer: deferred-1 ran")
	end)
	butler:Defer(function()
		table.insert(order, "deferred-2")
		print("  Defer: deferred-2 ran")
	end)
	butler:Defer(function()
		table.insert(order, "deferred-3")
		print("  Defer: deferred-3 ran")
	end)

	butler:Destroy()

	print("  Cleanup order:", table.concat(order, " → "))
	-- LIFO: 3 → 2 → 1
	_result(15, "Defer() runs at Destroy in LIFO order",
		order[1] == "deferred-3" and order[2] == "deferred-2" and order[3] == "deferred-1",
		("Order was: %s (expected 3→2→1)"):format(table.concat(order, "→"))
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 16 — butler:Batch() — RxJS CompositeDisposable
-- ═══════════════════════════════════════════════════════════════════════════════
_header(16, "Batch() — RxJS CompositeDisposable")

do
	local butler = Butler.new()

	local a = makeDestroyable("Batch-A")
	local b = makeDestroyable("Batch-B")
	local cDisc = makeDisconnectable("Batch-C")
	local dFnCalled = false

	butler:Batch({
		a,
		b,
		cDisc,
		function() dFnCalled = true ; print("  Batch fn item ran") end,
	})

	print("  Count after Batch of 4:", butler:Count())
	butler:Destroy()

	_result(16, "Batch() tracks and cleans all items",
		a.destroyed and b.destroyed and cDisc.disconnected and dFnCalled,
		not a.destroyed       and "a not destroyed"
		or not b.destroyed    and "b not destroyed"
		or not cDisc.disconnected and "cDisc not disconnected"
		or not dFnCalled      and "fn not called"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 17 — butler:OnClean() — RxJS finalize() teardown observer
-- ═══════════════════════════════════════════════════════════════════════════════
_header(17, "OnClean() — RxJS finalize() observer")

do
	local butler = Butler.new()
	local cleanCount = 0

	butler:OnClean(function()
		cleanCount += 1
		print("  OnClean observer #1 fired. cleanCount:", cleanCount)
	end)
	butler:OnClean(function()
		cleanCount += 1
		print("  OnClean observer #2 fired. cleanCount:", cleanCount)
	end)

	-- Call Clean() (reuse) first — observers fire once
	butler:Clean()
	print("  cleanCount after Clean():", cleanCount)

	-- Observers remain after Clean(), fire again on Destroy()
	butler:Destroy()
	print("  cleanCount after Destroy():", cleanCount)

	_result(17, "OnClean() fires on every Clean() and Destroy()",
		cleanCount == 4, -- 2 on Clean + 2 on Destroy
		("cleanCount expected 4, got %d"):format(cleanCount)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 18 — butler:Wrap() — TC39 Symbol.dispose / DisposableHandle
-- ═══════════════════════════════════════════════════════════════════════════════
_header(18, "Wrap() — TC39 Explicit Resource Management / DisposableHandle")

do
	local butler = Butler.new()

	local resource = makeDestroyable("Wrapped-Resource")
	resource.value = 42
	function resource:getValue() return self.value end

	local handle = butler:Wrap(resource)

	-- Test proxy: method call should reach the underlying object
	print("  handle:getValue():", handle:getValue())

	-- Early dispose
	handle:Dispose()
	print("  resource.destroyed after Dispose():", resource.destroyed)
	print("  Count after early Dispose():", butler:Count())

	-- Destroy the butler — resource should NOT be double-cleaned
	butler:Destroy()
	print("  resource.destroyed after butler:Destroy():", resource.destroyed)

	_result(18, "Wrap() proxies methods + Dispose() early-removes",
		handle:getValue() == 42 and resource.destroyed and butler:Count() == 0,
		handle:getValue() ~= 42 and "Proxy method did not work"
		or not resource.destroyed and "Dispose() did not clean resource"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 19 — butler:Tween() — correct Cancel+Destroy lifecycle
-- ═══════════════════════════════════════════════════════════════════════════════
_header(19, "Tween() — correct Cancel+Destroy lifecycle")

do
	local butler = Butler.new()

	-- Create a real Part in workspace to tween
	local part = Instance.new("Part")
	part.Anchored = true
	part.Parent = workspace

	local startPos = part.Position
	local info = TweenInfo.new(10, Enum.EasingStyle.Linear) -- long tween
	local tween = butler:Tween(part, info, { Position = startPos + Vector3.new(0, 100, 0) })

	print("  Tween PlaybackState after play:", tween.PlaybackState)
	task.wait(0.2)

	local posAtStop = part.Position
	print("  Part Y position before cancel:", posAtStop.Y)

	-- Destroy butler mid-tween — should Cancel the tween
	butler:Destroy()

	local posAfterCancel = part.Position
	print("  Part Y position after butler:Destroy():", posAfterCancel.Y)

	-- Position should be roughly the same — tween was cancelled, not completed
	local moved = math.abs(posAfterCancel.Y - startPos.Y)
	print("  Total movement (should be < 5):", moved)

	part:Destroy()

	_result(19, "Tween() Cancel()s mid-play on Destroy",
		moved < 5,
		("Part moved %.2f units — tween may not have been cancelled"):format(moved)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 20 — butler:Scope() — child butler lifetime tied to parent
-- ═══════════════════════════════════════════════════════════════════════════════
_header(20, "Scope() — child Butler destroyed with parent")

do
	local parent = Butler.new()
	local child  = parent:Scope()

	local parentFn  = makeDestroyable("ParentObj")
	local childFn   = makeDestroyable("ChildObj")
	local grandchildFn = makeDestroyable("GrandchildObj")

	parent:Add(parentFn)
	child:Add(childFn)

	-- Even a grandchild scope
	local grandchild = child:Scope()
	grandchild:Add(grandchildFn)

	print("  parent count:", parent:Count())
	print("  child count:", child:Count())
	print("  grandchild count:", grandchild:Count())
	print("  child:IsAlive():", child:IsAlive())

	-- Destroy parent — cascades to child and grandchild
	parent:Destroy()

	print("  child:IsAlive() after parent:Destroy():", child:IsAlive())
	print("  grandchild:IsAlive() after parent:Destroy():", grandchild:IsAlive())

	_result(20, "Scope() cascades Destroy through child chain",
		parentFn.destroyed and childFn.destroyed and grandchildFn.destroyed
		and not child:IsAlive() and not grandchild:IsAlive(),
		not parentFn.destroyed    and "parentFn not destroyed"
		or not childFn.destroyed  and "childFn not destroyed"
		or not grandchildFn.destroyed and "grandchildFn not destroyed"
		or child:IsAlive()        and "child still alive after parent destroy"
		or grandchild:IsAlive()   and "grandchild still alive"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 21 — butler:LinkToInstance() — auto-destroy when instance is removed
-- ═══════════════════════════════════════════════════════════════════════════════
_header(21, "LinkToInstance() — auto-Destroy on instance removal")

do
	local butler = Butler.new()
	local cleaned = false

	butler:OnClean(function()
		cleaned = true
		print("  OnClean fired from LinkToInstance trigger")
	end)

	-- Create a dummy instance to link to
	local dummy = Instance.new("Part")
	dummy.Parent = workspace
	butler:LinkToInstance(dummy)

	print("  butler:IsAlive() before destroy:", butler:IsAlive())

	-- Destroying the instance should auto-Destroy the butler
	dummy:Destroy()
	task.wait()

	print("  butler:IsAlive() after instance destroyed:", butler:IsAlive())
	print("  OnClean ran:", cleaned)

	_result(21, "LinkToInstance() triggers Destroy when instance destroyed",
		not butler:IsAlive() and cleaned,
		butler:IsAlive() and "Butler still alive after instance destroy"
		or not cleaned and "OnClean did not fire"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 22 — butler:LinkToInstance(inst, allowReAdd=true) — calls Clean not Destroy
-- ═══════════════════════════════════════════════════════════════════════════════
_header(22, "LinkToInstance(inst, true) — Clean not Destroy on instance removal")

do
	local butler = Butler.new()
	local cleanCount = 0

	butler:OnClean(function()
		cleanCount += 1
		print("  Clean observer fired, count:", cleanCount)
	end)

	-- Add tasks that will be cleaned
	local obj = makeDestroyable("ReAddObj")
	butler:Add(obj)

	local dummy = Instance.new("Part")
	dummy.Parent = workspace
	butler:LinkToInstance(dummy, true) -- allowReAdd = true

	dummy:Destroy()
	task.wait()

	print("  butler:IsAlive() after Clean:", butler:IsAlive())
	print("  obj.destroyed:", obj.destroyed)

	-- Butler should still be alive (Clean was called, not Destroy)
	-- We can add new tasks to it
	if butler:IsAlive() then
		local obj2 = makeDestroyable("ReAddObj2")
		butler:Add(obj2)
		print("  Re-added obj2 — Count:", butler:Count())
		butler:Destroy()
		print("  obj2.destroyed:", obj2.destroyed)
		_result(22, "LinkToInstance(true) calls Clean; butler stays alive",
			butler:IsAlive() == false and obj.destroyed and obj2.destroyed,
			"Re-add flow failed"
		)
	else
		_result(22, "LinkToInstance(true) calls Clean; butler stays alive",
			false, "Butler was destroyed instead of cleaned"
		)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 23 — butler:Clean() — resets without destroying; tasks re-addable
-- ═══════════════════════════════════════════════════════════════════════════════
_header(23, "Clean() — resets tasks, butler stays alive")

do
	local butler = Butler.new()

	local round1 = makeDestroyable("Round1")
	butler:Add(round1)
	print("  Count before Clean():", butler:Count())

	butler:Clean()
	print("  Count after Clean():", butler:Count())
	print("  round1.destroyed:", round1.destroyed)
	print("  butler:IsAlive() after Clean():", butler:IsAlive())

	-- Re-add tasks after clean
	local round2 = makeDestroyable("Round2")
	butler:Add(round2)
	print("  Count after re-add:", butler:Count())

	butler:Destroy()
	print("  round2.destroyed:", round2.destroyed)

	_result(23, "Clean() clears tasks but keeps butler alive for re-use",
		round1.destroyed and round2.destroyed and butler:Count() == 0,
		not round1.destroyed and "round1 not destroyed by Clean()"
		or not round2.destroyed and "round2 not destroyed by Destroy()"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 24 — double Destroy() is a safe no-op
-- ═══════════════════════════════════════════════════════════════════════════════
_header(24, "Destroy() double-call is a safe no-op")

do
	local butler = Butler.new()
	local fnCallCount = 0
	butler:Add(function()
		fnCallCount += 1
		print("  Cleanup fn called, count:", fnCallCount)
	end)

	butler:Destroy()
	butler:Destroy() -- should do nothing
	butler:Destroy() -- should do nothing

	print("  fnCallCount (should be 1):", fnCallCount)

	_result(24, "Double Destroy() safe no-op — fn called exactly once",
		fnCallCount == 1,
		("fn was called %d times (expected 1)"):format(fnCallCount)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 25 — butler:Snapshot() — debug view of tracked tasks
-- ═══════════════════════════════════════════════════════════════════════════════
_header(25, "Snapshot() — debug task inspection")

do
	local butler = Butler.new()

	butler:Add(function() end)              -- anonymous fn
	butler:Add(function() end, nil, "myFn") -- labeled fn
	butler:Set("namedConn", makeDestroyable("NC"))

	local snap = butler:Snapshot()
	print("  Snapshot:")
	for k, v in pairs(snap) do
		print(("    [%s] = '%s'"):format(tostring(k), v))
	end

	-- Check named key appears in snapshot
	local hasNamed = snap["namedConn"] ~= nil
	local hasLabeled = false
	for _, v in pairs(snap) do
		if v == "myFn" then hasLabeled = true end
	end

	butler:Destroy()

	_result(25, "Snapshot() returns readable task map",
		hasNamed and hasLabeled,
		not hasNamed   and "'namedConn' missing from snapshot"
		or not hasLabeled and "'myFn' label missing from snapshot"
		or nil
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 26 — Error tolerance: bad task doesn't abort the clean chain
-- ═══════════════════════════════════════════════════════════════════════════════
_header(26, "Error tolerance — bad task doesn't crash clean chain")

do
	local butler = Butler.new()
	local afterErrorRan = false

	-- This task errors on cleanup
	butler:Add(function()
		print("  [bad task] about to error...")
		error("Intentional error in cleanup task!")
	end)

	-- This task should still run even after the error above
	butler:Defer(function()
		afterErrorRan = true
		print("  [after error] Defer ran successfully despite earlier error")
	end)

	-- Should warn but not crash
	butler:Destroy()

	_result(26, "Error in one task doesn't abort the rest",
		afterErrorRan,
		"Defer after erroring task did not run"
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TEST 27 — WaitFor() — cancels the wait if butler is destroyed mid-wait
-- ═══════════════════════════════════════════════════════════════════════════════
_header(27, "WaitFor() — cancels if butler destroyed during wait")

do
	local butler = Butler.new()
	local folder = Instance.new("Folder")
	folder.Parent = workspace

	local waitResult: Instance? = nil
	local waitDone = false

	-- Run WaitFor in a separate task so we can destroy the butler while waiting
	task.spawn(function()
		waitResult = butler:WaitFor(folder, "NeverAddedChild", math.huge)
		waitDone = true
		print("  WaitFor() returned:", tostring(waitResult))
	end)

	task.wait(0.1) -- let WaitFor start
	print("  Destroying butler while WaitFor is in progress...")
	butler:Destroy()
	task.wait(0.2) -- let scheduler settle

	folder:Destroy()

	_result(27, "WaitFor() thread cancelled when butler destroyed",
		waitResult == nil,
		"WaitFor() returned a non-nil value when it should have been cancelled"
	)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ─── SUMMARY ─────────────────────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════════════════

task.wait(0.2)
print("\n" .. string.rep("═", 72))
print("  BUTLER TEST SUITE — COMPLETE")
print(string.rep("═", 72))
print(("  Total:  %d"):format(total))
print(("  Passed: %d"):format(passed))
if failed > 0 then
	warn(("  Failed: %d X < check warnings above"):format(failed))
else
	print(("  Failed: %d"):format(failed))
end
print(string.rep("═", 72))

if failed == 0 then
	print("\n ALL TESTS PASSED — Butler is working correctly!")
else
	warn(("\n %d TEST(S) FAILED — review the output above"):format(failed))
end
