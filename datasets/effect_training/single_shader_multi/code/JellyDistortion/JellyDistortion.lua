
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

---@language GLSL
local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

void main() 
{
    gl_FragColor = texture2D(inputImageTexture, textureCoord);
}
]]

---@language GLSL
local geometry_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;        
uniform sampler2D inputImageTexture;
uniform float u_rotation;           // 旋转角度（弧度）
uniform float u_rotationAxis;       // 旋转轴方向角（弧度）

mat2 rotationMatrix(float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return mat2(c, -s, s, c);
}

vec2 rotateAroundAxis(vec2 p, float angle, float axisAngle)
{
    vec2  centerOffset = p - 0.5;              
    float axisSlope    = tan(axisAngle);        
    float perpSlope    = tan(axisAngle + 1.5707963267948966); 

    vec2 foot;
    foot.x = (centerOffset.y - axisSlope * centerOffset.x) / (perpSlope - axisSlope);
    foot.y = foot.x * perpSlope;

    vec2  rotated = rotationMatrix(-angle) * (centerOffset - foot) + foot;
    return rotated + 0.5;                    
}

vec2 mirrorRepeat(vec2 uv)
{
    return abs(mod(uv + 1.0, 2.0) - 1.0);
}

void main()
{
    vec2 rotatedUV = rotateAroundAxis(textureCoord, u_rotation, u_rotationAxis);
    gl_FragColor  = texture2D(inputImageTexture, mirrorRepeat(rotatedUV));
}
]]

local ae_keyframes = {
    ['LumiGeometry_21-effect0#rotation#number'] =
{
	{
		{0.33333333, 0, 0.66666667, 1, }, 
		{0.2, 2.8, }, 
		{{-25, }, {0, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
    ['LumiGeometry_21-effect0#rotationAxis#number'] =
{
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0, 0.04, }, 
		{{0, }, {14, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.04, 0.08, }, 
		{{14, }, {28, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.08, 0.12, }, 
		{{28, }, {42, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.12, 0.16, }, 
		{{42, }, {56, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.16, 0.2, }, 
		{{56, }, {70, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.2, 0.24, }, 
		{{70, }, {84, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.24, 0.28, }, 
		{{84, }, {98, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.28, 0.32, }, 
		{{98, }, {112, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.32, 0.36, }, 
		{{112, }, {126, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.36, 0.4, }, 
		{{126, }, {140, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.4, 0.44, }, 
		{{140, }, {154, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.44, 0.48, }, 
		{{154, }, {168, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.48, 0.52, }, 
		{{168, }, {182, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.52, 0.56, }, 
		{{182, }, {196, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.56, 0.6, }, 
		{{196, }, {210, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.6, 0.64, }, 
		{{210, }, {224, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.64, 0.68, }, 
		{{224, }, {238, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.68, 0.72, }, 
		{{238, }, {252, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.72, 0.76, }, 
		{{252, }, {266, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.76, 0.8, }, 
		{{266, }, {280, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.8, 0.84, }, 
		{{280, }, {294, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.84, 0.88, }, 
		{{294, }, {308, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.88, 0.92, }, 
		{{308, }, {322, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.92, 0.96, }, 
		{{322, }, {336, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.96, 1, }, 
		{{336, }, {350, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1, 1.04, }, 
		{{350, }, {364, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.04, 1.08, }, 
		{{364, }, {378, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.08, 1.12, }, 
		{{378, }, {392, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.12, 1.16, }, 
		{{392, }, {406, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.16, 1.2, }, 
		{{406, }, {420, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.2, 1.24, }, 
		{{420, }, {434, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.24, 1.28, }, 
		{{434, }, {448, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.28, 1.32, }, 
		{{448, }, {462, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.32, 1.36, }, 
		{{462, }, {476, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.36, 1.4, }, 
		{{476, }, {490, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.4, 1.44, }, 
		{{490, }, {504, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.44, 1.48, }, 
		{{504, }, {518, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.48, 1.52, }, 
		{{518, }, {532, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.52, 1.56, }, 
		{{532, }, {546, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.56, 1.6, }, 
		{{546, }, {560, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.6, 1.64, }, 
		{{560, }, {574, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.64, 1.68, }, 
		{{574, }, {588, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.68, 1.72, }, 
		{{588, }, {602, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.72, 1.76, }, 
		{{602, }, {616, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.76, 1.8, }, 
		{{616, }, {630, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.8, 1.84, }, 
		{{630, }, {644, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.84, 1.88, }, 
		{{644, }, {658, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.88, 1.92, }, 
		{{658, }, {672, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.92, 1.96, }, 
		{{672, }, {686, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{1.96, 2, }, 
		{{686, }, {700, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2, 2.04, }, 
		{{700, }, {714, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.04, 2.08, }, 
		{{714, }, {728, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.08, 2.12, }, 
		{{728, }, {742, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.12, 2.16, }, 
		{{742, }, {756, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.16, 2.2, }, 
		{{756, }, {770, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.2, 2.24, }, 
		{{770, }, {784, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.24, 2.28, }, 
		{{784, }, {798, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.28, 2.32, }, 
		{{798, }, {812, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.32, 2.36, }, 
		{{812, }, {826, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.36, 2.4, }, 
		{{826, }, {840, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.4, 2.44, }, 
		{{840, }, {854, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.44, 2.48, }, 
		{{854, }, {868, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.48, 2.52, }, 
		{{868, }, {882, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.52, 2.56, }, 
		{{882, }, {896, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.56, 2.6, }, 
		{{896, }, {910, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.6, 2.64, }, 
		{{910, }, {924, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.64, 2.68, }, 
		{{924, }, {938, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.68, 2.72, }, 
		{{938, }, {952, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.72, 2.76, }, 
		{{952, }, {966, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.76, 2.8, }, 
		{{966, }, {980, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.8, 2.84, }, 
		{{980, }, {994, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.84, 2.88, }, 
		{{994, }, {1008, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.88, 2.92, }, 
		{{1008, }, {1022, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{2.92, 2.96, }, 
		{{1022, }, {1036, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
}

local AETools = AETools or {}
AETools.__index = AETools

local function deepcopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        -- setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function AETools.new(attrs)
    if attrs == nil then return nil end

    local self = setmetatable({}, AETools)
    self.attrs = attrs

    local max_frame = 0
    local min_frame = 100000
    for _,v in pairs(attrs) do
        for i = 1, #v do
            local content = v[i]
            local cur_frame_min = content[2][1]
            local cur_frame_max = content[2][2]
            max_frame = math.max(cur_frame_max, max_frame)
            min_frame = math.min(cur_frame_min, min_frame)

            if  content[4] ~= nil
            and content[5] ~= nil
            and (content[4][1] == 6413 or content[4][1] == 6415)
            and content[5][1] == 0
            then
                local p0 = content[3][1]
                local totalLen = 0
                local lenInfo = {}
                lenInfo[0] = 0
                for test=1,200,1 do
                    local coord = self._cubicBezier3D(content[3][1], content[3][3], content[3][4], content[3][2], test/200)
                    local length = 0
                    if #p0 >= 3 then
                        length = math.sqrt((coord[1]-p0[1])*(coord[1]-p0[1])+(coord[2]-p0[2])*(coord[2]-p0[2])+(coord[3]-p0[3])*(coord[3]-p0[3]))
                    else
                        length = math.sqrt((coord[1]-p0[1])*(coord[1]-p0[1])+(coord[2]-p0[2])*(coord[2]-p0[2]))
                    end
                    p0 = coord
                    totalLen = totalLen + length
                    lenInfo[test] = totalLen
                end
                for test=1,200,1 do
                    lenInfo[test] = lenInfo[test]/(lenInfo[200]+0.000001)
                end
                content['lenInfo'] = lenInfo
            end
        end
    end

    self.all_frame = max_frame - min_frame
    self.min_frame = min_frame

    return self
end

function AETools:CurFrame(_p)
    local frame = math.floor(_p*self.all_frame)
    return frame + self.min_frame
end

function AETools:AllFrame(_p)
    return self.all_frame
end

function AETools._remap01(a,b,x)
    if x < a then return 0 end
    if x > b then return 1 end
    return (x-a)/(b-a)
end

function AETools._cubicBezier(p1, p2, p3, p4, t)
    local t2 = t * t
    local t3 = t2 * t
    local _t = 1 - t
    local _t2 = _t * _t
    local _t3 = _t2 * _t
    return {
        p1[1] * _t3 + 3 * p2[1] * _t2 * t + 3 * p3[1] * _t * t2 + p4[1] * t3,
        p1[2] * _t3 + 3 * p2[2] * _t2 * t + 3 * p3[2] * _t * t2 + p4[2] * t3,
    }
end

function AETools._cubicBezier3D(p1, p2, p3, p4, t)
    local t2 = t * t
    local t3 = t2 * t
    local _t = 1 - t
    local _t2 = _t * _t
    local _t3 = _t2 * _t
    local value = {
        p1[1] * _t3 + 3 * p2[1] * _t2 * t + 3 * p3[1] * _t * t2 + p4[1] * t3,
        p1[2] * _t3 + 3 * p2[2] * _t2 * t + 3 * p3[2] * _t * t2 + p4[2] * t3,
        0,
    }
    if #p1 >= 3 then
        value[3] = p1[3] * _t3 + 3 * p2[3] * _t2 * t + 3 * p3[3] * _t * t2 + p4[3] * t3
    end
    return value
end

function AETools:_cubicBezierSpatial(lenInfo, p1, p2, p3, p4, t)
    local p = 0
    if t <= 0 then
        p = 0
    elseif t >= 1 then
        p = 1
    else
        local ts = 199
        local te = 200
        for i=1,200,1 do
            if lenInfo[i] >= t then
                te = i
                ts = i-1
                break
            end
        end
        p = ts/200. + 0.005*(t-lenInfo[ts])/(lenInfo[te]-lenInfo[ts]+0.000001)
    end
    return self._cubicBezier3D(p1, p2, p3, p4, p)
end

function AETools:_cubicBezier01(_bezier_val, p, y_len)
    local x = self:_getBezier01X(_bezier_val, p, y_len)
    return self._cubicBezier(
        {0,0},
        {_bezier_val[1], _bezier_val[2]},
        {_bezier_val[3], _bezier_val[4]},
        {1, y_len},
        x
    )[2]
end

function AETools:AllFrame()
    return self.all_frame
end

function AETools:_getBezier01X(_bezier_val, x, y_len)
    local ts = 0
    local te = 1
    -- divide and conque
    local times = 1
    repeat
        local tm = (ts+te)*0.5
        local value = self._cubicBezier(
            {0,0},
            {_bezier_val[1], _bezier_val[2]},
            {_bezier_val[3], _bezier_val[4]},
            {1, y_len},
            tm)
        if(value[1]>x) then
            te = tm
        else
            ts = tm
        end
        times = times +1
    until(te-ts < 0.001 and times < 50)

    return (te+ts)*0.5
end

function AETools._mix(a, b, x, type)
    if type == 1 then
        return a * (1-x) + b * x
    end
    return a + x
end

function AETools:GetVal(_name, _progress)
    local content = self.attrs[_name]
    if content == nil then
        return nil
    end

    local cur_frame = _progress

    for i = 1, #content do
        local info = content[i]
        local start_frame = info[2][1]
        local end_frame = info[2][2]
        if cur_frame >= start_frame and cur_frame < end_frame then
            local cur_progress = self._remap01(start_frame, end_frame, cur_frame)
            local bezier = info[1]
            local value_range = info[3]
            local y_len = 1
            if (value_range[2][1] == value_range[1][1] and info[5] and info[5][1]==0 and #(value_range[1])==1) then
                y_len = 0
            end

            if info[5] and info[5][1] == 2 then
                return deepcopy(info[3][1])
            end

            if #bezier > 4 then
                -- currently scale attrs contains more than 4 bezier values
                local res = {}
                for k = 1, 3 do
                    local cur_bezier = {bezier[k], bezier[k+3], bezier[k+3*2], bezier[k+3*3]}
                    local p = self:_cubicBezier01(cur_bezier, cur_progress, y_len)
                    res[k] = self._mix(value_range[1][k], value_range[2][k], p, y_len)
                end
                return res

            else
                local p = self:_cubicBezier01(bezier, cur_progress, y_len)
                if  info[4] ~= nil
                and info[5] ~= nil
                and (info[4][1] == 6413 or info[4][1] == 6415)
                and info[5][1] == 0
                then
                    local coord = self:_cubicBezierSpatial(
                        info['lenInfo'],
                        value_range[1], 
                        value_range[3], 
                        value_range[4], 
                        value_range[2], 
                        p
                    )
                    if info[4][1] == 6415 then
                        return {coord[1], coord[2]}
                    end
                    return coord
                end

                if type(value_range[1]) == "table" then
                    local res = {}
                    for j = 1, #value_range[1] do
                        res[j] = self._mix(value_range[1][j], value_range[2][j], p, y_len)
                    end
                    return res
                end
                return self._mix(value_range[1], value_range[2], p, y_len)
            end
        end
    end

    local first_info = content[1]
    local start_frame = first_info[2][1]
    if cur_frame<start_frame then
        return deepcopy(first_info[3][1])
    end

    local last_info = content[#content]
    local end_frame = last_info[2][2]
    if cur_frame>=end_frame then
        return deepcopy(last_info[3][2])
    end

    return nil
end

JellyDistortion = {}

function JellyDistortion:matchWithId(effectId)
    return 'KFM KSkr JellyDistortion' == effectId
end

function JellyDistortion.createWithId(effectId)
    if not JellyDistortion:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        currentWidth = 0,
        currentHeight = 0,
        speed = 0,
        progress = 0
    }
    o = newObject(o, JellyDistortion)
    o:init()
    return o;
end

function JellyDistortion:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:initWithShaderStrings(vs, geometry_fs)
    self.program:bind()
    self.program:sendUniformi('inputImageTexture', 0)

    local buffer = {}
    glGenBuffers(1,buffer) 
    self.vertexBuffer = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)

    self.keyframes = AETools.new(ae_keyframes)
end

function JellyDistortion:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- Speed
        self.speed = val1 / 100.0
    elseif index == 2 then
        self.progress = val1 / 100.0
    end
end

function JellyDistortion:resize(width, height)

end

function JellyDistortion:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function JellyDistortion:remap(value, srcMin, srcMax, dstMin, dstMax)
    return dstMin + (value - srcMin) * (dstMax - dstMin) / (srcMax - srcMin)
end

function JellyDistortion:clamp(val, min, max)
    return math.min(math.max(val, min), max)
end

function JellyDistortion:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local speed = self:remap(self:clamp(self.speed, 0, 1), 0, 1, 0.5, 2.0)
    local aeDuration = 2.0
    local curTime = self.progress * speed * aeDuration ---AnimationMode.Loop
    -- local aeTime = curTime % aeDuration

    local rotation = self.keyframes:GetVal('LumiGeometry_21-effect0#rotation#number', curTime)[1]
    local rotationAxis = self.keyframes:GetVal('LumiGeometry_21-effect0#rotationAxis#number', curTime)[1]
    rotationAxis = math.abs(rotationAxis % 90) < 0.01 and rotationAxis - 0.01 or rotationAxis

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.program:bind()
    self.program:sendUniformf('u_rotation', math.rad(rotation))
    self.program:sendUniformf('u_rotationAxis', math.rad(rotationAxis))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    print('^^^^' .. rotation .. '&&&' .. rotationAxis)
end

function JellyDistortion:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end
    