local mt = {

    __add = function(a, b)
        return ccsphere_vec3(a.x + b.x, a.y + b.y, a.z + b.z)
    end,

    __sub = function(a, b)
        return ccsphere_vec3(a.x - b.x, a.y - b.y, a.z - b.z)
    end,

    __mul = function(a, b)
        if type(b) == "number" then
            return ccsphere_vec3(a.x * b, a.y * b, a.z * b)
        else
            return ccsphere_vec3(a.x * b.x, a.y * b.y, a.z * b.z)
        end
    end,

    __div = function(a, b)
        if type(b) == "number" then
            return ccsphere_vec3(a.x / b, a.y / b, a.z / b)
        else
            return ccsphere_vec3(a.x / b.x, a.y / b.y, a.z / b.z)
        end
    end,

    __unm = function(a)
        return ccsphere_vec3(-a.x, -a.y, -a.z)
    end,

    __eq = function(a, b)
        return a.x == b.x and a.y == b.y and a.z == b.z
    end,

    __lt = function(a, b)
        return a.x <= b.x and a.y <= b.y and a.z <= b.z
    end,

    __index = {
        dot = function(self, v)
            return self.x * v.x + self.y * v.y + self.z * v.z
        end,

        length = function(self)
            return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
        end,

        normalize = function(self)
            local length = self:length()
            return ccsphere_vec3(self.x / length, self.y / length, self.z / length)
        end,

        reflect = function(self, normal)
            return normal * 2 * self:dot(normal) - self
        end,

        mix = function(self, v, t)
            return self * t + v * (1 - t)
        end,

        cross = function(self, right)
            return ccsphere_vec3(self.y*right.z-self.z*right.y,
                    self.z*right.x-self.x*right.z,
                    self.x*right.y-self.y*right.x)
        end
    }
}

function ccsphere_vec3(var1, var2, var3)
    local v

    v = {x = var1, y = var2, z = var3}

    setmetatable(v, mt)
    return v
end
