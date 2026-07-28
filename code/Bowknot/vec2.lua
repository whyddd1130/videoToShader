local mt = {

    __add = function(a, b)
        if type(b) == "number" then
            return vec2(a.x + b, a.y + b)
        else
            return vec2(a.x + b.x, a.y + b.y)
        end
    end,

    __sub = function(a, b)
        if type(b) == "number" then
            return vec2(a.x - b, a.y - b)
        else
            return vec2(a.x - b.x, a.y - b.y)
        end
    end,

    __mul = function(a, b)
        if type(b) == "number" then
            return vec2(a.x * b, a.y * b)
        else
            return vec2(a.x * b.x, a.y * b.y)
        end
    end,

    __div = function(a, b)
        if type(b) == "number" then
            return vec2(a.x / b, a.y / b)
        else
            return vec2(a.x / b.x, a.y / b.y)
        end
    end,

    __unm = function(a)
        return vec2(-a.x, -a.y)
    end,

    __eq = function(a, b)
        return a.x == b.x and a.y == b.y
    end,

    __lt = function(a, b)
        return a.x < b.x or a.x == b.x and a.y < b.y
    end,

    __index = {
        dot = function(self, v)
            return self.x * v.x + self.y * v.y
        end,

        perp = function(self)
            return vec2(-self.y, self.x)
        end,

        length = function(self)
            return math.sqrt(self.x * self.x + self.y * self.y)
        end,

        normalize = function(self)
            local length = self:length()
            return vec2(self.x / length, self.y / length)
        end,

        reflect = function(self, normal)
            return normal * 2 * self:dot(normal) - self
        end,

        min = function(self, v)
            local min = vec2(self.x, self.y)
            if v.x < min.x then min.x = v.x end
            if v.y < min.y then min.y = v.y end
            return min
        end,

        max = function(self, v)
            local max = vec2(self.x, self.y)
            if v.x > max.x then max.x = v.x end
            if v.y > max.y then max.y = v.y end
            return max
        end,

        linearInterpolate = function(self, v, t)
            return self * (1 - t) + v * t
        end
    }
}

function makeMatrix(m00, m01, m10, m11)
    return {{m00,m01}, {m10,m11}}
end

function makeRotation(rad)
    local cosRad = math.cos(rad)
    local sinRad = math.sin(rad)
    return makeMatrix(cosRad, sinRad, -sinRad, cosRad)
end

function mulMat2xV2(rM, v)
    return vec2(rM[1][1]*v.x+rM[2][1]*v.y, rM[1][2]*v.x+rM[2][2]*v.y)
end

function vec2(var1, var2)
    local v
    if type(var1) == 'table'
    then
        v = {x = var1[var2 * 2 + 1], y = var1[var2 * 2 + 2]}
    elseif type(var1) == 'userdata'
    then
        v = {x = var1[var2 * 2], y = var1[var2 * 2 + 1]}
    else
        v = {x = var1, y = var2}
    end
    setmetatable(v, mt)
    return v
end
