# MacroBindings
Use conditional bindings inside macros - World of Warcraft addon

This library adds support for executing bindings based on macro conditions. Bindings can be dynamically mapped to macros based on where the macros are placed on the action bars. The library has a self-contained state handler and tracker for the macro namespace and current action bar loadout.

## Example usage in macros
- Interact when possible, otherwise jump
```
/binding [@anyinteract,exists] Interact With Target; Jump
```
- Use extra action button when it's available, otherwise cast spell
```#showtooltip
/binding [extrabar] Extra Action Button 1
/cast Living Flame
```
## API
The API is very slim. A macro body can be tested to see which conditions will be configured in a macro driver. Apart from that, different page drivers and binding ID templates can be used to work with action bar addons that do not follow the Blizzard standard.
```lua
-- @param body        : The body of the macro to parse.
-- @return conditions : A table containing all conditions found in the macro.
MacroBindings:ParseBody(body)

-- @param barID       : The ID of the bar to drive.
-- @param condition   : The condition to execute the response on.
-- @param response    : The response to execute. Optional. Defaults to result of condition.
MacroBindings:SetPageDriver(barID, condition, response)

-- @param barID       : The ID of the bar to get binding keys for.
-- @param template    : The binding template to use, e.g. ACTIONBUTTON%d
MacroBindings:SetBindingTemplate(barID, template)
```
