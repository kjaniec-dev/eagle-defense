-- Palette-indexed CPU framebuffer plus deterministic scaling to RGB ImageData.
-- All arithmetic is integer, so output bytes do not depend on the FPU.
local ffi = require("ffi")

local M = {}

function M.new(w, h, fill)
  local px = {}
  fill = fill or 0
  for i = 1, w * h do
    px[i] = fill
  end
  return { w = w, h = h, px = px }
end

function M.get(c, x, y)
  if x < 0 or y < 0 or x >= c.w or y >= c.h then
    return nil
  end
  return c.px[y * c.w + x + 1]
end

function M.set(c, x, y, v)
  if x < 0 or y < 0 or x >= c.w or y >= c.h then
    return
  end
  c.px[y * c.w + x + 1] = v
end

function M.fill_rect(c, x, y, w, h, v)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      M.set(c, xx, yy, v)
    end
  end
end

-- Copies a sprite ({w, h, px} with 0 = transparent). Optional clip rect.
function M.blit(c, s, x, y, clip)
  for sy = 0, s.h - 1 do
    for sx = 0, s.w - 1 do
      local v = s.px[sy * s.w + sx + 1]
      if v ~= 0 then
        local dx, dy = x + sx, y + sy
        if
          not clip
          or (dx >= clip[1] and dy >= clip[2] and dx < clip[1] + clip[3] and dy < clip[2] + clip[4])
        then
          M.set(c, dx, dy, v)
        end
      end
    end
  end
end

-- Remaps every pixel whose mask value is set through lut (palette -> palette).
function M.apply_mask(c, mask, lut)
  for i = 1, c.w * c.h do
    if mask[i] then
      c.px[i] = lut[c.px[i]]
    end
  end
end

function M.copy(c)
  local n = M.new(c.w, c.h, 0)
  for i = 1, c.w * c.h do
    n.px[i] = c.px[i]
  end
  return n
end

-- Crops a region into a new canvas.
function M.crop(c, x, y, w, h)
  local n = M.new(w, h, 0)
  for yy = 0, h - 1 do
    for xx = 0, w - 1 do
      n.px[yy * w + xx + 1] = M.get(c, x + xx, y + yy) or 1
    end
  end
  return n
end

------------------------------------------------------------------------------
-- RGB image buffers (plain byte arrays, 3 bytes per pixel)

function M.rgb_new(w, h, r, g, b)
  local buf = ffi.new("uint8_t[?]", w * h * 3)
  for i = 0, w * h - 1 do
    buf[i * 3] = r or 0
    buf[i * 3 + 1] = g or 0
    buf[i * 3 + 2] = b or 0
  end
  return { w = w, h = h, buf = buf }
end

-- Nearest-neighbour integer scale of an indexed canvas into an RGB image at
-- offset (ox, oy).
function M.rgb_blit_nearest(img, c, pal_rgb, scale, ox, oy)
  for y = 0, c.h * scale - 1 do
    local sy = math.floor(y / scale)
    local dy = oy + y
    if dy >= 0 and dy < img.h then
      for x = 0, c.w * scale - 1 do
        local dx = ox + x
        if dx >= 0 and dx < img.w then
          local pv = c.px[sy * c.w + math.floor(x / scale) + 1]
          local col = pal_rgb[pv]
            or error(("bad pixel %s at %d,%d"):format(tostring(pv), math.floor(x / scale), sy))
          local o = (dy * img.w + dx) * 3
          img.buf[o] = col[1]
          img.buf[o + 1] = col[2]
          img.buf[o + 2] = col[3]
        end
      end
    end
  end
end

-- Copies a region of one RGB image into another (nearest, integer zoom).
function M.rgb_copy(dst, src, sx, sy, w, h, dx, dy, zoom)
  zoom = zoom or 1
  for y = 0, h * zoom - 1 do
    for x = 0, w * zoom - 1 do
      local px = sx + math.floor(x / zoom)
      local py = sy + math.floor(y / zoom)
      local tx, ty = dx + x, dy + y
      if px >= 0 and py >= 0 and px < src.w and py < src.h then
        if tx >= 0 and ty >= 0 and tx < dst.w and ty < dst.h then
          local so = (py * src.w + px) * 3
          local o = (ty * dst.w + tx) * 3
          dst.buf[o] = src.buf[so]
          dst.buf[o + 1] = src.buf[so + 1]
          dst.buf[o + 2] = src.buf[so + 2]
        end
      end
    end
  end
end

function M.rgb_fill(img, x, y, w, h, col)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      if xx >= 0 and yy >= 0 and xx < img.w and yy < img.h then
        local o = (yy * img.w + xx) * 3
        img.buf[o] = col[1]
        img.buf[o + 1] = col[2]
        img.buf[o + 2] = col[3]
      end
    end
  end
end

-- "Sharp bilinear" fit: nearest prescale by `pre` (integer), then one
-- bilinear resample to (dw, dh). The source coordinate of destination pixel
-- x is ((x + 0.5) * S / D - 0.5) with S = canvas width * pre and D = dw; it
-- is evaluated as an exact rational (num / den) so the result is
-- bit-identical everywhere. Bilinear weights are rounded once at the end.
function M.rgb_sharp_bilinear(c, pal_rgb, pre, dw, dh)
  local sw, sh = c.w * pre, c.h * pre
  local img = M.rgb_new(dw, dh)
  -- prescaled texel lookup (clamped)
  local function texel(x, y)
    if x < 0 then
      x = 0
    elseif x >= sw then
      x = sw - 1
    end
    if y < 0 then
      y = 0
    elseif y >= sh then
      y = sh - 1
    end
    local i = math.floor(y / pre) * c.w + math.floor(x / pre) + 1
    return pal_rgb[c.px[i]]
  end
  -- (x + 0.5) * S / D - 0.5 = ((2x + 1) * S - D) / (2D)
  local denx, deny = 2 * dw, 2 * dh
  for y = 0, dh - 1 do
    local numy = (2 * y + 1) * sh - dh
    local y0 = math.floor(numy / deny)
    local fy = numy - y0 * deny -- weight of y0 + 1, out of deny
    for x = 0, dw - 1 do
      local numx = (2 * x + 1) * sw - dw
      local x0 = math.floor(numx / denx)
      local fx = numx - x0 * denx
      local a, b = texel(x0, y0), texel(x0 + 1, y0)
      local cc, d = texel(x0, y0 + 1), texel(x0 + 1, y0 + 1)
      local den = denx * deny
      local o = (y * dw + x) * 3
      for k = 1, 3 do
        local top = a[k] * (denx - fx) + b[k] * fx
        local bot = cc[k] * (denx - fx) + d[k] * fx
        local v = top * (deny - fy) + bot * fy
        img.buf[o + k - 1] = math.floor((2 * v + den) / (2 * den))
      end
    end
  end
  return img
end

-- Encodes an RGB image to PNG bytes via love.image (CPU only).
function M.rgb_to_png(img)
  local data = love.image.newImageData(img.w, img.h, "rgba8")
  local p = ffi.cast("uint8_t*", data:getFFIPointer())
  for i = 0, img.w * img.h - 1 do
    p[i * 4] = img.buf[i * 3]
    p[i * 4 + 1] = img.buf[i * 3 + 1]
    p[i * 4 + 2] = img.buf[i * 3 + 2]
    p[i * 4 + 3] = 255
  end
  return data:encode("png"):getString()
end

function M.to_rgb(c, pal_rgb, scale)
  scale = scale or 1
  local img = M.rgb_new(c.w * scale, c.h * scale)
  M.rgb_blit_nearest(img, c, pal_rgb, scale, 0, 0)
  return img
end

return M
