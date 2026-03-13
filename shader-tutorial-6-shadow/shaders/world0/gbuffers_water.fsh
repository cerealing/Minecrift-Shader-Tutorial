#version 460 compatibility

#include "/lib/blocks.glsl"

const bool colortex7Clear = true;

uniform sampler2D gtexture;

uniform float alphaTestRef = 0.1;

in float entityId;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0,7 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 data;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	data = vec4(0.0);

	if (color.a < alphaTestRef) {
		discard;
	}

	if (entityId == BLOCK_WATER)
	{
		data = vec4(7.0 / 255.0, color.a, 0.0, 1.0);
	}
}