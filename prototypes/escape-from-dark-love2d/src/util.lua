local M = {}

M.TAU = math.pi * 2

function M.clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

function M.distance(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

function M.normalize(dx, dy)
  local length = math.sqrt(dx * dx + dy * dy)
  if length <= 0.0001 then
    return 0, 0, 0
  end
  return dx / length, dy / length, length
end

function M.angleTo(dy, dx)
  if math.atan2 then
    return math.atan2(dy, dx)
  end
  return math.atan(dy, dx)
end

function M.angleDelta(a, b)
  local d = (b - a) % M.TAU
  if d > math.pi then d = d - M.TAU end
  return d
end

function M.rectContains(rect, x, y)
  return x >= rect.x and x <= rect.x + rect.w
    and y >= rect.y and y <= rect.y + rect.h
end

function M.setColor(color)
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.clampToWorld(x, y, w, h, worldW, worldH)
  return M.clamp(x, 0, worldW - w), M.clamp(y, 0, worldH - h)
end

function M.choice(t)
  return t[love.math.random(#t)]
end

return M
