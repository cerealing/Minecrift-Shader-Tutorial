#version 460 compatibility

out vec4 color;
out vec4 lmtexcoord;

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, (m)[2].z )
#define projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec4 toClipSpace3(vec3 viewSpacePosition)
{
    return vec4(projMAD(gl_ProjectionMatrix, viewSpacePosition), -viewSpacePosition.z);
}

void main()
{
    vec3 position = mat3(gl_ModelViewMatrix) * vec3(gl_Vertex) + gl_ModelViewMatrix[3].xyz;
    color = gl_Color;
    lmtexcoord.xy = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vec2 lmcoord = gl_MultiTexCoord1.xy / 240.0;
    lmtexcoord.zw = lmcoord;
    gl_Position = toClipSpace3(position);
}