sprint_lite = {}
local player_info = {}

--Get settingtypes
local max_stamina = tonumber(minetest.settings:get("sprint_lite_max_stamina")) or 20
local speed_multiplier = tonumber(minetest.settings:get("sprint_lite_speed_multiplier")) or 1.75
local jump_multiplier = tonumber(minetest.settings:get("sprint_lite_jump_multiplier")) or 1.25
local step_interval = tonumber(minetest.settings:get("sprint_lite_step_interval")) or 0.15
local drain_hunger = minetest.settings:get_bool("sprint_lite_drain_hunger", false)
local drain_hunger_amount = tonumber(minetest.settings:get("sprint_lite_hunger_amount")) or 0.03
local stamina_drain = tonumber(minetest.settings:get("sprint_lite_stamina_drain")) or 0.5
local stamina_regen = tonumber(minetest.settings:get("sprint_lite_stamina_regen")) or 0.1
local stamina_threshold = tonumber(minetest.settings:get("sprint_lite_stamina_threshold")) or 8
local spawn_particles = minetest.settings:get_bool("sprint_lite_spawn_particles", true)
local respawn_stamina = tonumber(minetest.settings:get("sprint_lite_respawn_stamina")) or max_stamina/4
local require_ground = minetest.settings:get_bool("sprint_lite_require_ground", false)
local hudbars_enabled = false
local S = minetest.get_translator(minetest.get_current_modname())

--API functions
sprint_lite.set_stamina = function(name, amount, add)
    if type(name) ~= "string" or type(amount) ~= "number" then
        minetest.log("error", "[sprint_lite] set_stamina: Wrong input data! Expected string and number, got " .. type(name) .. " and " .. type(amount))
        return false
    end
    if not player_info[name] then
        minetest.log("error", "[sprint_lite] set_stamina: Can't find player " .. name)
        return false
    end
    local stamina = 0
    if not add and amount < 0 then
        minetest.log("error", "[sprint_lite] set_stamina: value can't be lower than 0 when setting stamina")
        return false
    end
    if add then
        stamina = player_info[name].stamina + amount
    else
        stamina = amount
    end
    if stamina > max_stamina then
        stamina = max_stamina
    elseif stamina < 0 then
        stamina = 0
    end
    player_info[name].stamina = stamina
    return player_info[name].stamina
end

sprint_lite.get_stamina = function(name)
    if not player_info[name] then
        minetest.log("error", "[sprint_lite] get_stamina: Can't find player " .. name)
        return false
    end
    return player_info[name].stamina
end

--Mod checks
if minetest.get_modpath("hudbars") then
    hb.register_hudbar(
        "stamina",
        0xFFFFFF,
        S("Stamina"),
        {
            bar = "sprint_lite_bar.png",
            icon = "sprint_lite_icon.png",
            bgicon = "sprint_lite_bg.png"
        },
        0,
        max_stamina,
        false)
    hudbars_enabled = true
end

if not minetest.get_modpath("hbhunger") and drain_hunger then
    minetest.log("error", "[sprint_lite] hbhunger is not enabled/installed! Hunger drain is disabled")
    drain_hunger = false
end

--Initialization functions
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    player_info[name] = {ref = player, stamina = respawn_stamina, previous_stamina = 0, sprinting = false, grounded = false}
    if hudbars_enabled then hb.init_hudbar(player, "stamina", player_info[name].stamina, max_stamina) end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player_info[name] = nil
end)

minetest.register_on_respawnplayer(function(player)
    local name = player:get_player_name()
    player_info[name].stamina = respawn_stamina
end)

--Global step function
local sprint_timer = 0

minetest.register_globalstep(function(dtime)

    sprint_timer = sprint_timer + dtime
    if sprint_timer < step_interval then return end

    for playername,playerstats in pairs(player_info) do

        local pos = playerstats.ref:get_pos()
        local keys = playerstats.ref:get_player_control()
        local node = minetest.get_node_or_nil({x = pos.x, y = pos.y - 0.5, z = pos.z})

        if node and minetest.registered_nodes[node.name] and
        (minetest.registered_nodes[node.name].walkable or minetest.registered_nodes[node.name].liquidtype ~= "none") then
            playerstats.grounded = true
        else
            playerstats.grounded = false
        end
        
        local climbable = false
        
        if (keys.aux1 and (keys.sneak or keys.jump)) then
            local snodes = {
                            n = minetest.get_node_or_nil({x = pos.x, y = pos.y, z = pos.z + 0.5}),
                            s = minetest.get_node_or_nil({x = pos.x, y = pos.y, z = pos.z - 0.5}),
                            w = minetest.get_node_or_nil({x = pos.x - 0.5, y = pos.y, z = pos.z}),
                            e = minetest.get_node_or_nil({x = pos.x + 0.5, y = pos.y, z = pos.z}),
                            }
            
            for _,snode in pairs(snodes) do
            
                if snode and minetest.registered_nodes[snode.name] and minetest.registered_nodes[snode.name].climbable then
                    climbable = true
                end
            
            end
        end

        print(require_ground, playerstats.grounded, not require_ground)
        if (keys.aux1 and keys.up and not keys.left and not keys.right and not keys.down and not keys.sneak) or (climbable and ((keys.aux1 and keys.sneak) or (keys.aux1 and keys.jump))) then
            if ((require_ground and playerstats.grounded) or not require_ground) and
            ((not playerstats.sprinting and playerstats.stamina > stamina_threshold) or (playerstats.sprinting and playerstats.stamina > 0)) and
            playerstats.ref:get_hp() > 0 then
                if not playerstats.sprinting then
                    playerstats.sprinting = true
                    player_monoids.speed:add_change(playerstats.ref, speed_multiplier, "sprint_lite_sprinting")
                    player_monoids.jump:add_change(playerstats.ref, jump_multiplier, "sprint_lite_jumping")
                end
            else
                playerstats.sprinting = false
                player_monoids.speed:del_change(playerstats.ref, "sprint_lite_sprinting")
                player_monoids.jump:del_change(playerstats.ref, "sprint_lite_jumping")
            end
        else
            if playerstats.sprinting then
                playerstats.sprinting = false
                player_monoids.speed:del_change(playerstats.ref, "sprint_lite_sprinting")
                player_monoids.jump:del_change(playerstats.ref, "sprint_lite_jumping")
            end
        end

        if playerstats.sprinting and playerstats.stamina > 0 then

            playerstats.stamina = playerstats.stamina - stamina_drain
            if playerstats.stamina < 0 then playerstats.stamina = 0 end

            if drain_hunger then
                local hunger = hbhunger.hunger[playername]
                hunger = hunger - drain_hunger_amount
                if hunger < 0 then hunger = 0 end
                hbhunger.hunger[playername] = hunger
                hbhunger.set_hunger_raw(playerstats.ref)
            end

            if spawn_particles then

                local texture = "tnt_smoke.png"
                local glow = 0
                local acceleration = {x = 0, y = -9.8, z = 0}

                if playerstats.grounded and minetest.registered_nodes[node.name] then
                    if minetest.registered_nodes[node.name].tiles and
                    type(minetest.registered_nodes[node.name].tiles[1]) == "string" then
                        texture = minetest.registered_nodes[node.name].tiles[1]
                    end
                    if minetest.registered_nodes[node.name].liquidtype ~= "none" then
                        acceleration = {x = 0, y = 0, z = 0}
                    end
                    glow = minetest.registered_nodes[node.name].light_source or 0
                end

                minetest.add_particlespawner({
                    amount = math.random(4, 8),
                    time = 0.05,
                    minpos = {x=-0.35, y=-0.4, z=-0.35},
                    maxpos = {x=0.35, y=-0.4, z=0.35},
                    minvel = {x=-0.25, y=1, z=-0.25},
                    maxvel = {x=0.25, y=3, z=0.25},
                    minacc = acceleration,
                    maxacc = acceleration,
                    minexptime = 1.5,
                    maxexptime = 2.5,
                    minsize = 0.3,
                    maxsize = 1.25,
                    collisiondetection = true,
                    collision_removal = false,
                    attached = playerstats.ref,
                    texture = texture,
                    glow = glow
                })
            end

        elseif playerstats.stamina < max_stamina and playerstats.ref:get_hp() > 0 then
            playerstats.stamina = playerstats.stamina + stamina_regen
            if playerstats.stamina > max_stamina then playerstats.stamina = max_stamina end
        end

        if playerstats.stamina ~= playerstats.previous_stamina then
            playerstats.previous_stamina = playerstats.stamina
            if hudbars_enabled then
                local new_bar = "sprint_lite_bar.png^[colorize:#0c9a32:200"
                local new_icon = "sprint_lite_icon.png^[colorize:#11ea48:100"

                if playerstats.stamina < stamina_threshold then
                    new_bar = "sprint_lite_bar.png^[colorize:#b34102:200"
                    new_icon = "sprint_lite_icon.png^[colorize:#ff5b03:100"
                end

                hb.change_hudbar(playerstats.ref, "stamina", playerstats.stamina, nil, new_icon, nil, new_bar)
            end
        end

    end
    sprint_timer = 0
end)
