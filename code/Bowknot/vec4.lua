local mt = {

    __add = function(a, b)
        return vec4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
    end,

    __sub = function(a, b)
        return vec4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
    end,

    __mul = function(a, b)
        if type(b) == "number" then
            return vec4(a.x * b, a.y * b, a.z * b, a.w * b)
        else
            return vec4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w)
        end
    end,

    __div = function(a, b)
        if type(b) == "number" then
            return vec4(a.x / b, a.y / b, a.z / b, a.w / b)
        else
            return vec4(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w)
        end
    end,

    __unm = function(a)
        return vec4(-a.x, -a.y, -a.z, -a.w)
    end,

    __eq = function(a, b)
        return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w
    end,

    __lt = function(a, b)
        return a.x <= b.x and a.y <= b.y and a.z <= b.z and a.w <= b.w
    end,

    __index = {
        dot = function(self, v)
            return self.x * v.x + self.y * v.y + self.z * v.z + self.w * v.w
        end,

        length = function(self)
            return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w)
        end,

        normalize = function(self)
            local length = self:length()
            return vec4(self.x / length, self.y / length, self.z / length, self.w / length)
        end,

        reflect = function(self, normal)
            return normal * 2 * self:dot(normal) - self
        end,

        mix = function(self, v, t)
            return self * t + v * (1 - t)
        end
    }
}

function vec4(var1, var2, var3, var4)
    local v

    v = {x = var1, y = var2, z = var3, w = var4}

    setmetatable(v, mt)
    return v
end
