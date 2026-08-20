
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

#define DRAW_POINTS 0 // draw the center points
#define DRAW_GAP_LINE 0 // draw the gap line

#define NUM 100
vec4 chipInfo[NUM];

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float shatterFrame;
uniform int repetitions;

float rnd(vec2 s) //-1~1
{
    return 1. - 2. * fract(sin(s.x * 253.13 + s.y * 341.41) * 589.19);
}

float rand(float x) //0~1
{
    return fract(sin(x * 873.15) * 519.19);
}

vec2 MoveOffset(int idx, float t)
{
    vec2 center = vec2(0.0);
    vec2 offset = vec2(0.);

    float radVal = rand(float(idx + 1)) + 0.1; //0.1~1.1
    vec2 centerPos = chipInfo[idx].xy;
    vec2 diff = centerPos - center;
    float dist = length(diff);
    if(t > 0.0)
    {
        vec2 initVel = normalize(diff) * dist;

        //offset = initVel * t + vec2(0., 1.) * t * t * - 0.5; 
        offset = initVel * t; 
    }
    return offset;
}

int GetNearPos(vec2 p)
{
    vec2 v = chipInfo[0].xy;
    int idx = 0;
    for(int c = 0; c < repetitions; c++)
    {
        vec2 vc = chipInfo[c].xy;
        vec2 vp2 = vc-p;
        vec2 vp = v-p;
        if(dot(vp2, vp2) < dot(vp, vp))
        {
            v = vc;
            idx = c;
        }
    }
    return idx;
}

float GetGapFactor(vec2 p){
    vec2 center = vec2(0.0);

    vec2 v=vec2(1E3);
    vec2 v2=vec2(1E4);
    //find the most near pos v and v2
    for(int c = 0; c < repetitions; c++)
    {
        vec2 vc=chipInfo[c].xy;
        if(length(vc-p)<length(v-p))
        {
            v2=v;
            v=vc;
        }
        else if(length(vc-p)<length(v2-p))
        {
            v2=vc;
        }
    }
    //check for whether p is at the middle of v and v2
    float factor= abs(length(dot(p-v,normalize(v-v2)))-length(dot(p-v2,normalize(v-v2))))
        +.002*length(p-center);
    factor=7E-4/factor;
    if(length(v-v2)<4E-3) factor=0.;
    if(factor<.01) factor = 0.;
    return factor;

}

void main() 
{
    float finalColAlpha = 0.0;
    vec2 p = textureCoord * 2.0 - vec2(1.0);
    vec2 center = vec2(0.0);
    float isNear = 0.0;

    float time = shatterFrame;

    for(int c = 0; c < repetitions; c++)
    {
        //generate Random point 
        float angle = floor(rnd(vec2(float(c), 387.44)) * 16.); //-15.0～15.0
        float dist = pow(rnd(vec2(float(c), 78.21)), 2.); //0~1.0
        vec2 vc = vec2(center.x + cos(angle) * sqrt(dist), center.y + sin(angle)* sqrt(dist));
        chipInfo[c].xy= vc.xy;

        chipInfo[c].zw = MoveOffset(c, time);
    }

    int belongIdx = -1;
    for(int c = 0; c < repetitions; c++)
    {
        vec2 rawPos = p - chipInfo[c].zw;

        int idx = GetNearPos(rawPos);
        if(idx == c)
        {
            belongIdx = c;
            break;
        }
    }

    vec3 finalCol = vec3(0.);

    if(belongIdx != -1)
    {
        vec2 moveOffset = chipInfo[belongIdx].zw;

        //calc the raw pos before the picture is broken
        vec2 rawPos = p - moveOffset;

        //calc the uv from the raw pos
        vec2 rawCoord = (rawPos + vec2(1.0)) * 0.5;

        vec2 brokenOffset = vec2(0.0);
        if (time > 0.0)
        {
            brokenOffset = vec2(rnd(vec2(belongIdx)) * .006);
        }
        vec2 uv = rawCoord.xy + brokenOffset;
        
        finalCol = texture2D(inputImageTexture, uv).rgb;
        finalColAlpha = texture2D(inputImageTexture, uv).a;

        if(time >= 0.)
        {
            if(uv.x > 1.||uv.x < 0.||uv.y > 1.|| uv.y < 0.)
            {
                finalCol = vec3(0.0);
                finalColAlpha = 0.0;
            }
        }
    }

   if (DRAW_GAP_LINE > 0)
   {
       //draw Gap line
       float gapFactor = GetGapFactor(p);
       finalCol=gapFactor*vec3(1.-finalCol.xyz)+(1.-gapFactor)*finalCol.xyz;

       if (DRAW_POINTS > 0)
       {
           //draw the points
           float isNear = 0.;
           for(int c = 0;c < repetitions; c++)
           {
               vec2 vc = chipInfo[c].xy;
               //get raw pos 
               if(length(vc-p)<0.01){
                   isNear = 1.;
               }
           }
           finalCol = finalCol *(1.-isNear);
       }
   }

    gl_FragColor = vec4(finalCol, finalColAlpha);
}
]]

Shatter = {}

function Shatter:matchWithId(effectId)
    return 'KFM KSkr Shatter' == effectId
end

function Shatter.createWithId(effectId)
    if not Shatter:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {}
    }
    o = newObject(o, Shatter)
    o:init()
    return o;
end

function Shatter:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function Shatter:valueType(index)
    if index == 1 then
        -- Repetitions
        return FM.AEValueType_OneDInt
    elseif index == 2 then
        -- ShatterFrame
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function Shatter:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- Repetitions
        self.program:bind()
        self.program:sendUniformi('repetitions', val1)
    elseif index == 2 then
        -- ShatterFrame
        self.program:bind()
        self.program:sendUniformf('shatterFrame', val1)
    end
end

function Shatter:updateTimeAndFrame(time)

end

function Shatter:resize(width, height)
end

function Shatter:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function Shatter:onDestroy()
end
    