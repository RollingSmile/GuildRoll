-- CsvSRLoader.lua
-- Very small CSV loader: builds lookup table for soft reserves

local CsvSRLoader = {}
CsvSRLoader.__index = CsvSRLoader

function CsvSRLoader:parse(csvText)
  local lookup = {}
  for line in string.gmatch(csvText, "[^\r\n]+") do
    local name, items = string.match(line, "^%s*([^,;]+)%s*,%s*(.+)$")
    if name then
      lookup[name] = {}
      for it in string.gmatch(items, "([^|]+)") do
        table.insert(lookup[name], it)
      end
    end
  end
  return lookup
end

return CsvSRLoader
