
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
varying vec2 textureCoordinate;

void main()
{
    textureCoordinate = position * 0.5 + 0.5;
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

const float TWO_PI = 6.2831853071795;
const float PI = 3.1415926535898;

varying vec2 textureCoordinate;

uniform int _WType;
uniform sampler2D inputImageTexture;
uniform float _Frequency;
uniform float _Amplitude;
uniform float _Phase;
uniform float _Speed;
uniform float _RotateAngle;
uniform vec2  _CanvasSize;
uniform float _Time;
uniform int _Pinning;
/*
 if x >= y then return 1 else return 0
 */
float if_ge(float x, float y)
{
    return step(y, x);
}

/*
 if x < y then return 1 else return 0
 */
float if_lt(float x, float y)
{
    return 1.0 - if_ge(x, y);
}

/*
 if x <= y then return 1 else return 0
 */
float if_le(float x, float y)
{
    return step(-y, -x);
}

/*
 return x > y then return 1 else return 0
 */
float if_gt(float x, float y)
{
    return 1.0 - if_le(x, y);
}

/*
 if x == y then return 1 else return 0
 */
float if_eq(float x, float y)
{
    return 1.0 - abs(sign(x - y) );
}

float randomXY(float x, float y)
{
    return fract(sin(x * 12.9898+ y * 4.1414) * 43758.5453 );
}

float sin_wave(in float x)
{
    return sin(TWO_PI * _Frequency * x + _Speed * _Time * TWO_PI - radians(_Phase) );
}

float f_sin(in float x)
{
    return _Amplitude * sin_wave(x);
}

float f_square(in float x)
{
    return sign(sin_wave(x) ) * _Amplitude;
}

float f_triangle(in float x)
{
    float tmpx = x * _Frequency + _Speed * _Time;
    float vfloor = floor(tmpx + 0.5);
    return (2.0 * abs(2.0 * (tmpx - vfloor)) - 1.0) * _Amplitude;
}

float f_sawtooth(in float x)
{
    float tmpx = x * _Frequency +_Speed * _Time + 0.5 + _Phase / 360.0;
    return _Amplitude * (2.0 * (tmpx - floor(tmpx + 0.5) ) );
}

float f_circle(in float x)
{
    float wave_width = 1.0 /_Frequency;
    float nx = 2.0 * mod(x +(_Speed * _Time + _Phase / 360.0) * wave_width, wave_width) /wave_width;
    nx = mix(nx, 2.0 + nx, if_lt(nx, 0.0) );
    return _Amplitude * sign(nx - 1.0) * sqrt(0.25 - pow(mod(nx, 1.0) - 0.5, 2.0) );
}

float f_semicircle(in float x)
{
    float wave_width =  1.0 / _Frequency;
    float xc = mod(x + (_Speed *_Time + _Phase / 360.0)* wave_width, wave_width) * _Frequency;
    xc = mix(xc, 1.0 + xc, if_lt(xc, 0.0));
    return -2.0 * _Amplitude * (sqrt(0.25 - pow(xc - 0.5, 2.0)) - 0.2);
}

float f_uncircle(in float x)
{
    float wave_width = 1.0 /_Frequency;
    float nx = 2.0 * mod(x +(_Speed * _Time + _Phase / 360.0) * wave_width, wave_width) /wave_width;
    nx = mix(nx, 2.0 + nx, if_lt(nx, 0.0) );
    return _Amplitude * sign(nx - 1.0) *
    (0.5 - sqrt(0.25 - pow(mod(nx, 1.0) - 0.5, 2.0) ));
}

float noise(in float x)
{
    float quatient = floor(x * _Frequency * 2.0);
    float remainder = x - quatient;
    return randomXY(quatient, remainder) * 2.0 - 1.0;
}

float f_noise(in float x)
{
    return _Amplitude * noise(x + _Time * _Speed);
}

float f_smoothnoise(in float x)
{
    float val = (x+_Time * _Speed * 100.) * 20.0 *_Frequency;
    float i = floor(val);
    float f = val - i;
    float p0 = _Amplitude * 0.2* (2.0 * randomXY(i, 13.0) - 1.0);
    float p1 = _Amplitude * 0.2 *(2.0 * randomXY(i+1.0, 13.0) - 1.0);
    return mix(p0, p1, f*f*(3.0 - 2.0*f));
}

float wave(float x)
{
    float wtype = floor(float(_WType));
    if(wtype == 1.0){
        return f_sin(x);
    }else if(wtype == 2.0){
        return f_square(x);
    }else if(wtype == 3.0){
        return f_triangle(x);
    }else if(wtype == 4.0){
        return f_sawtooth(x);
    }else if(wtype == 5.0){
        return f_circle(x);
    }else if(wtype == 6.0){
        return f_semicircle(x);
    }else if(wtype == 7.0){
        return f_uncircle(x);
    }else if(wtype == 8.0){
        return f_noise(x);
    }else if(wtype == 9.0){
        return f_smoothnoise(x);
    }
}

float pinning(vec2 uv) {
   float pmode = floor(float(_Pinning));
   
   float limittop = step(0.25, uv.y) + step(uv.y, 0.25) * uv.y / 0.25;
   float limitbottom = step(uv.y, 0.75) + step(0.75, uv.y) * (1.0 - uv.y) / 0.25;
   float limitleft = step(0.25, uv.x) + step(uv.x, 0.25) * uv.x / 0.25;
   float limitright = step(uv.x, 0.75) + step(0.75, uv.x) * (1.0 - uv.x) / 0.25;
   
   if (pmode == 1.0)
   {
       return 1.0;
   }
   else if (pmode == 2.0)
   {
       return limittop * limitbottom * limitleft * limitright;
   }
   else if (pmode == 3.0)
   {
       /* todo */
       return 1.0;
   }
   else if (pmode == 4.0)
   {
       return limitleft;
   }
   else if (pmode == 5.0)
   {
       return limittop;
   }
   else if (pmode == 6.0)
   {
       return limitright;
   }
   else if (pmode == 7.0)
   {
       return limitbottom;
   }
   else if (pmode == 8.0)
   {
       return limitleft * limitright;
   }
   else if (pmode == 9.0)
   {
       return limittop * limitbottom;
   }
}

void main()
{
    float rad = radians(_RotateAngle + 180.0);
    float fsin = sin(rad);
    float fcos = cos(rad);
    vec2 dir = vec2(fsin, -fcos);
    vec2 uv =textureCoordinate;
    float offset = wave(dot(uv * _CanvasSize, dir));
    uv += vec2(fcos, fsin) * pinning(uv) * offset / _CanvasSize;
    vec4 col = texture2D(inputImageTexture, uv);
    float if_out_range = if_gt(if_lt(uv.x, 0.0) +
                               if_gt(uv.x, 1.0) +
                               if_lt(uv.y, 0.0) +
                               if_gt(uv.y, 1.0),
                               0.0);
    col = mix(col, vec4(0.0), if_out_range);
    gl_FragColor = col;
}
]]

WaveWarp = {}

function WaveWarp:matchWithId(effectId)
    return 'KFM KSkr WaveWarp' == effectId
end

function WaveWarp.createWithId(effectId)
    if not WaveWarp:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {}
    }
    o = newObject(o, WaveWarp)
    o:init()
    return o;
end

function WaveWarp:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function WaveWarp:valueType(index)
    if index == 1 then
        -- WaveType
        return FM.AEValueType_OneDInt
    elseif index == 2 then
        -- WaveHeight
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- WaveWidth
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- Direction
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- WaveSpeed
        return FM.AEValueType_OneDFloat
    elseif index == 6 then
        -- Pinning
        return FM.AEValueType_OneDInt
    elseif index == 7 then
        -- Phase
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function WaveWarp:updateValue(index, val1, val2, val3)
    local program = self.drawer:getProgram()
    program:bind()
    if index == 1 then
        -- WaveType
        -- val1 is a index(starts with 1, not 0) of [sin | square | triangle | sawtooth | circle | semicircle | uncircle | noise | smoothnoise]
        program:sendUniformi("_WType", val1)
    elseif index == 2 then
        -- WaveHeight
        program:sendUniformf("_Amplitude", val1)
    elseif index == 3 then
        -- WaveWidth
        program:sendUniformf("_Frequency", 0.5 / val1)
    elseif index == 4 then
        -- Direction
        program:sendUniformf("_RotateAngle", val1)
    elseif index == 5 then
        -- WaveSpeed
        program:sendUniformf("_Speed", val1)
    elseif index == 6 then
        -- Pinning
        -- val1 is a index(starts with 1, not 0) of [None | AllEdges | centering | leftedge | topedge | rightedge | bottomedge | horizontaledge | verticaledge]
        program:sendUniformi("_Pinning", val1)
    elseif index == 7 then
        -- Phase
        program:sendUniformf("_Phase", val1)
    end

end

function WaveWarp:updateTimeAndFrame(time, frame)
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("_Time", time)
end

function WaveWarp:resize(width, height)
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("_CanvasSize", width, height)
end

function WaveWarp:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function WaveWarp:onDestroy()
end
    