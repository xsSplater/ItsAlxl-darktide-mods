local mod = get_mod("DynamicCrosshair")
local Breed = require("scripts/utilities/breed")
local Recoil = require("scripts/utilities/recoil")
local Sway = require("scripts/utilities/sway")

local OPT_PREFIX_VILLAINS = "^villains_"
local OPT_PREFIX_HEROES = "^heroes_"
local OPT_PREFIX_PROPS = "^props_"

local CROSSHAIR_POSITION_LERP_SPEED = 35
local CROSSHAIR_COMPONENTS = {
    "center",
    "up",
    "down",
    "left",
    "right",
    "up_left",
    "up_right",
    "bottom_left",
    "bottom_right",
    "charge_mask_left",
    "charge_mask_right",
}

local MAX_DISTANCE = 50
local HIT_IDX_DISTANCE = 2
local HIT_IDX_ACTOR = 4

local color_types = {
    villains = {
        mod:get("villains_a"),
        mod:get("villains_r"),
        mod:get("villains_g"),
        mod:get("villains_b"),
    },
    heroes = {
        mod:get("heroes_a"),
        mod:get("heroes_r"),
        mod:get("heroes_g"),
        mod:get("heroes_b"),
    },
    props = {
        mod:get("props_a"),
        mod:get("props_r"),
        mod:get("props_g"),
        mod:get("props_b"),
    },
}

local compat_custom_color = mod:get("compat_custom_color")
local latest_color_type = nil

local _rgba_to_idx = function(rgba)
    if rgba == "a" then
        return 1
    end
    if rgba == "r" then
        return 2
    end
    if rgba == "g" then
        return 3
    end
    if rgba == "b" then
        return 4
    end
    return -1
end

mod.on_setting_changed = function(id)
    local val = mod:get(id)

    if id == "compat_custom_color" then
        compat_custom_color = val
    elseif string.find(id, OPT_PREFIX_VILLAINS) then
        local key = string.sub(id, string.len(OPT_PREFIX_VILLAINS))
        color_types.villains[_rgba_to_idx(key)] = val
    elseif string.find(id, OPT_PREFIX_HEROES) then
        local key = string.sub(id, string.len(OPT_PREFIX_HEROES))
        color_types.heroes[_rgba_to_idx(key)] = val
    elseif string.find(id, OPT_PREFIX_PROPS) then
        local key = string.sub(id, string.len(OPT_PREFIX_PROPS))
        color_types.props[_rgba_to_idx(key)] = val
    end
end

local _crosshair_raycast = function(physics_world, shoot_position, shoot_direction)
    return PhysicsWorld.raycast(physics_world, shoot_position, shoot_direction, MAX_DISTANCE, "all", "collision_filter", "filter_debug_unit_selector")
end

mod:hook(CLASS.HudElementCrosshair, "_crosshair_position", function(func, self, dt, t, ui_renderer)
    -- modified from scripts/ui/hud/elements/crosshair/hud_element_crosshair
    local target_x = 0
    local target_y = 0
    local ui_renderer_scale = ui_renderer.scale
    local parent = self._parent
    local player_extensions = parent:player_extensions()
    local weapon_extension = player_extensions and player_extensions.weapon
    local player_camera = parent:player_camera()

    if weapon_extension and player_camera then
        local unit_data_extension = player_extensions.unit_data
        local first_person_extention = player_extensions.first_person
        local first_person_unit = first_person_extention:first_person_unit()
        local shoot_rotation = Unit.world_rotation(first_person_unit, 1)
        local shoot_position = Unit.world_position(first_person_unit, 1)
        local recoil_template = weapon_extension:recoil_template()
        local recoil_component = unit_data_extension:read_component("recoil")
        local movement_state_component = unit_data_extension:read_component("movement_state")
        shoot_rotation = Recoil.apply_weapon_recoil_rotation(recoil_template, recoil_component, movement_state_component, shoot_rotation)
        local sway_component = unit_data_extension:read_component("sway")
        local sway_template = weapon_extension:sway_template()
        shoot_rotation = Sway.apply_sway_rotation(sway_template, sway_component, movement_state_component, shoot_rotation)
        local shoot_direction = Quaternion.forward(shoot_rotation)
        local range = MAX_DISTANCE

        -- This crashes sometimes for reasons I can't figure out, so let's just pcall it
        local raycast_success, raycast_hits = pcall(_crosshair_raycast, player_extensions.interactor._physics_world, shoot_position, shoot_direction)
        local color_type = nil
        if raycast_success and raycast_hits then
            local closest_hit = nil
            local num_hits = #raycast_hits
            for i = 1, num_hits do
                local hit = raycast_hits[i]
                local distance = hit[HIT_IDX_DISTANCE]
                local unit = Actor.unit(hit[HIT_IDX_ACTOR])
                if unit and unit ~= parent._player.player_unit then
                    if distance < range then
                        closest_hit = hit
                        range = distance
                    end
                end
            end

            if closest_hit then
                local unit = Actor.unit(closest_hit[HIT_IDX_ACTOR])
                local health_extension = ScriptUnit.has_extension(unit, "health_system")
                if health_extension and health_extension:is_alive() then
                    local target_unit_data_extension = ScriptUnit.extension(unit, "unit_data_system")
                    local breed = target_unit_data_extension and target_unit_data_extension:breed()

                    if Breed.is_minion(breed) then
                        color_type = "villains"
                    end
                    if Breed.is_player(breed) then
                        color_type = "heroes"
                    end
                    if Breed.is_prop(breed) then
                        color_type = "props"
                    end
                end
            end
        end
        latest_color_type = color_type

        local world_aim_position = shoot_position + shoot_direction * range
        local screen_aim_position = Camera.world_to_screen(player_camera, world_aim_position)
        local abs_target_x = screen_aim_position.x
        local abs_target_y = screen_aim_position.y
        local pivot_position = self:scenegraph_world_position("pivot", ui_renderer_scale)
        local pivot_x = pivot_position[1]
        local pivot_y = pivot_position[2]
        target_x = abs_target_x - pivot_x
        target_y = abs_target_y - pivot_y
    end

    local current_x = self._crosshair_position_x * ui_renderer_scale
    local current_y = self._crosshair_position_y * ui_renderer_scale
    local ui_renderer_inverse_scale = ui_renderer.inverse_scale
    local lerp_t = math.min(CROSSHAIR_POSITION_LERP_SPEED * dt, 1)
    local x = math.lerp(current_x, target_x, lerp_t) * ui_renderer_inverse_scale
    local y = math.lerp(current_y, target_y, lerp_t) * ui_renderer_inverse_scale
    self._crosshair_position_y = y
    self._crosshair_position_x = x

    return x, y
end)

mod:hook_safe(CLASS.HudElementCrosshair, "_sync_active_crosshair", function(self)
    local widget = self._widget
    local base_def = self._crosshair_widget_definitions[self._crosshair_type]
    if widget and base_def then
        local color = nil
        if latest_color_type then
            color = color_types[latest_color_type]
        end

        if color then
            for _, part in ipairs(CROSSHAIR_COMPONENTS) do
                if widget.style[part] then
                    widget.style[part].color = color
                end
            end
        elseif not compat_custom_color then
            for _, part in ipairs(CROSSHAIR_COMPONENTS) do
                if widget.style[part] then
                    widget.style[part].color = base_def.style[part].color
                end
            end
        end
    end
end)