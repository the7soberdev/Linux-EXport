-- Runtime smoke test: exercises every module entry point once.
print("[driver] begin")

local hub = GENV.FischHub
assert(hub, "API not exported")

hub.scanner.refresh(true)
print("[driver] scanner:", hub.scanner.summary())

hub.minigame.tick()
print("[driver] minigame:", hub.minigame.status())

hub.esp.step()
hub.fishing.step()
print("[driver] fishing:", hub.fishing.stats().state)

assert(hub.economy.sell() == false, "sell should be false with no vendor")
assert(hub.quests.claim() == false, "quest should be false with no prompt")

hub.anti.scanStaff()
print("[driver] staff:", hub.anti.staffPresent)

hub.ui.select("MOVE")
hub.ui.select("ESP")
hub.ui.select("FISH")
hub.ui.notify("smoke test", "good")

hub.motion.setSpeed(32)
hub.motion.setNoclip(false)
hub.motion.stopFly()

assert(hub.learn.start() == false, "learn must degrade gracefully without namecall hook")
assert(hub.learn.tagNext("reel") == true, "tag must still record intent")
assert(hub.learn.stop() == 0, "no entries without a hook")
local applied = hub.learn.apply()
assert(applied.reel == nil, "nothing to apply")
print("[driver] learn: degraded cleanly")

assert(hub.economy.interact("sell", 1) == false, "no mechanism should fire")
print("[driver] economy mechanism:", hub.economy.mechanism)

print("[driver] minigame geometry:", hub.minigame.geometry, "confidence:", hub.minigame.confidence())
local stealth = hub.stealth
for _ = 1, 50 do
	local value = stealth.jitter(10, 0.3)
	assert(value >= 6.9 and value <= 13.1, "jitter out of range: " .. value)
end
print("[driver] jitter: bounded")

stealth.noteCatch()
stealth.noteCatch()
local limited, count, cap = stealth.rateLimited()
assert(type(count) == "number" and type(cap) == "number", "rate limit shape")
print(string.format("[driver] rate: %d/%d limited=%s", count, cap, tostring(limited)))

assert(stealth.blocked() == false, "nothing should block in an empty server")
stealth.engagePanic()
assert(hub.config.get("autoCast") == false, "panic must kill autofish")
assert(hub.config.get("esp") == false, "panic must kill esp")
stealth.releasePanic()
print("[driver] panic: clean")

print("[driver] stealth status:", stealth.status())
print("[driver] config save:", hub.config.save())
print("[driver] ok")
