# GLua Style Guide

## Spacing

- **Spaces around operators:** `local x = a * b + c`
- **Spaces after commas:** `myFunc(10, {3, 5})`
- **Tab indentation** (4-space width)
- **No spaces inside square brackets:** `local val = tab[5]`
- **Space after `--`:** `-- This is a comment`

## Newlines

- Never more than 2 consecutive newlines
- 1-2 newlines between top-level blocks
- 1 newline max between nested blocks
- Newline before `return` (unless single-line function)
- Split code into logical chunks with single newlines
- Newlines after guard clauses/early returns/assignments

## Operators & Comments

- Use Lua operators: `and`, `or`, `not`, `~=`
- **Avoid:** `&&`, `||`, `!`, `!=`
- Use Lua comments: `--` and `--[[ ]]`
- **Avoid:** `//` and `/* */`
- Avoid `continue` when possible (use early returns or inverted conditions)

## Naming

| Type | Style | Example |
|------|-------|---------|
| Local variables/functions | camelCase | `local myVariable = 10` |
| Constants | SCREAMING_SNAKE | `local MAX_VALUE = 25` |
| Globals | PascalCase | `GlobalVariable = 10` |
| Methods | PascalCase | `function obj:SetHealth()` |
| Throwaway | `_` | `for _, v in pairs(t) do` |

## Tables & Functions

**Multiline tables:**
```lua
local tbl = {
    key1 = value1,
    key2 = value2,
}
```

**Multiline function calls:**
```lua
myFunc(
    arg1,
    arg2,
    arg3
)
```

**Align assingments:**

If several variables are being assigned, align the `=` signs for readability
```lua
local veryLongVariableName = 10
local shortVar             = 20
```

## Code Organization

### Use `do...end` Blocks for Sections

Group related code into `do...end` blocks. This creates logical sections and scopes local variables to where they're used.

```lua
do -- MARK: Damage Calculations
	local pi    = math.pi
	local floor = math.floor

	local function CalculateBlast(radius)
		return pi * radius ^ 2
	end

	function ACF.Damage.Apply(ent, damage)
		local result = CalculateBlast(damage.Radius)
		-- ...

		return result
	end
end
```

**Benefits:**
- `-- MARK:` comments appear in VSCode minimap/outline for navigation
- Localized variables stay near the code that uses them
- Helper functions are scoped to their section
- Clear visual separation between features

**Don't** put all localized variables at the file top:
```lua
-- Bad: variables at top, unclear what they relate to
local pi    = math.pi
local floor = math.floor
local min   = math.min
local max   = math.max
-- ... 200 lines later, where are these used?
```

## Best Practices

### Return Early
```lua
-- Good
function test()
    if not valid then return end

    doStuff()
end

-- Bad (unnecessary nesting)
function test()
    if valid then
        doStuff()
    end
end
```

### Named Constants
```lua
-- Good
local MAX_HEALTH = 100
if health > MAX_HEALTH then

-- Bad
if health > 100 then  -- Magic number
```

### Complex Expressions
```lua
-- Good
local widthMod = amount * damageMult
local age      = 1 - lifetime / duration
local width    = widthMod * age

-- Bad
local width = ( amount * 5 ) * ( 1 - lifetime / duration )
```

### Long Conditions
```lua
-- Good
local isValid = IsValid(ent)
local isReady = ent:IsReady()

if isValid and isReady then

-- Bad
if IsValid(ent) and ent:IsReady() and ent:GetOwner():IsAdmin() then
```

## Numbers

- Leading zeros on decimals: `0.5` not `.5`
- No leading zeros on integers: `42` not `042`
- No trailing zeros: `0.5` not `0.500`

## Avoid

- Semicolons (no functional value in Lua)
- Unnecessary `IsValid()` checks (only where entity can become NULL)
- Unnecessary `tostring()` on numbers when concatenating
- Useless comments that restate obvious code
- Lines longer than ~110 characters

## Print with Varargs

```lua
-- Good
print("Health:", ply:Health(), "Pos:", ply:GetPos())

-- Bad
print("Health: " .. tostring(ply:Health()) .. " Pos: " .. tostring(ply:GetPos()))
```

