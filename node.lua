gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

util.no_globals()

local is_leader = (config.is_leader == "yes")
local last_sync_time = 0
local json = require "json"

-- Enable network sync via UDP
local udp = require "socket".udp()
udp:settimeout(0)
udp:setsockname("*", 4444) -- 4444 is the port we're listening on

local enable_audio = true -- fallback default

local sync_received = false

local function check_for_sync()
    local msg = udp:recieve()
    if msg == "start_now" then
        print("Sync message received!")
        sync_received = true
    end
end

local function image(file, duration)
    local img, ends
    return {
        prepare = function()
            img = resource.load_image{
                file = file,
            }
        end;
        start = function()
            ends = sys.now() + duration
        end;
        draw = function(pos)
            util.draw_correct(img, pos.x1, pos.y1, pos.x2, pos.y2)
            return sys.now() <= ends
        end;
        dispose = function()
            img:dispose()
        end;
    }
end

local function video(file, duration)
    local vid, ends
    return {
        prepare = function()
            print "video prepare"
            vid = resource.load_video{
                file = file,
                paused = true,
                raw = true,
                audio = enable_audio,
            }
        end;
        start = function()
            print "video start"
            ends = sys.now() + duration
        end;
        draw = function(pos)
            local state, width, height = vid:state()
            if state == "paused" then
                local x1, y1, x2, y2 = util.scale_into(pos.x2-pos.x1, pos.y2-pos.y1, width, height)
                vid:place(pos.x1+x1, pos.y1+y1, pos.x1+x2, pos.y1+y2):layer(1):start()
            end
            return sys.now() <= ends -- and (state == "paused" or state == "loaded")
        end;
        dispose = function()
            print "video dispose"
            vid:dispose()
        end;
    }
end

local function Runner(scheduler, pos)
    local cur, nxt, old

    local function prepare()
        assert(not nxt)
        nxt = scheduler.get_next()
        nxt.prepare()
    end
    local function down()
        assert(not old)
        old = cur
        cur = nil
    end
    local function switch()
        assert(nxt)
        cur = nxt
        cur.start()
        nxt = nil
    end
    local function dispose()
        old.dispose()
        old = nil
    end

    local function tick()
        if not nxt then
            prepare()
        end
        if old then
            dispose()
        end
        if not cur then
            switch()
        end
        if not cur.draw(pos) then
            down()
        end
    end

    return {
        tick = tick;
    }
end

local function cycled(items, offset)
    if #items == 0 then
        return nil, 0
    end
    offset = offset % #items + 1
    return items[offset], offset
end

local function Scheduler()
    local items = {}
    local offset = 0

    local function update(playlist)
        local new_items = {}
        for _, item in ipairs(playlist) do
            new_items[#new_items+1] = {
                file = resource.open_file(item.asset.asset_name),
                type = item.asset.type,
                duration = item.duration,
            }
        end
        items = new_items

        -- uncomment if a playlist change should start that playlist from the beginning
        -- offset = 0
    end

    local function get_next()
        local item
        print("next item?", offset, #items)
        item, offset = cycled(items, offset)
        pp(item)
        print(offset)
        item = item or { -- fallback?
            file = resource.open_file("empty.png"),
            type = "image",
            duration = 1,
        }
        return ({
            image = image,
            video = video,
        })[item.type](item.file:copy(), item.duration)
    end

    return {
        update = update,
        get_next = get_next,
    }
end

local playlist_1 = Scheduler()
local playlist_2 = Scheduler()

util.json_watch("config.json", function(config)
    playlist_1.update(config.playlist_1)
    playlist_2.update(config.playlist_2)
    enable_audio = (config.enable_audio == "yes")
end)

local runner_1 = Runner(playlist_1, {
    x1 = 0,
    y1 = 0,
    x2 = WIDTH/2,
    y2 = HEIGHT,
})

local runner_2 = Runner(playlist_2, {
    x1 = WIDTH/2,
    y1 = 0,
    x2 = WIDTH,
    y2 = HEIGHT,
})

function node.render()
    if not sync_received then
        check_for_sync()
        return
    end
    runner_1.tick()
    runner_2.tick()
end

function node.update()
     if is_leader and sys.now() - last_sync_time > 5 then -- every 5 seconds
        print("Sending sync command")
        udp:sendto("start_now", "255.255.255.255", 4444)
        last_sync_time = sys.now()
    end
end

function node.net_msg(sender, message)
    if not is_leader then
        local ok, data = pcall(json.decode, message)
        if ok and data.sync then
            local offset = data.sync - sys.now()
            print("Sync offset", offset)
        end
    end
end
