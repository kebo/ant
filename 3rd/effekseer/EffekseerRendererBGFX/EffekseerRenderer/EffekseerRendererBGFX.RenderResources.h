#pragma once
//#include "Effekseer.h"
#include "EffekseerRendererBGFX.RendererImplemented.h"

#include <string>
#include <vector>

namespace EffekseerRendererBGFX {
	namespace Backend {
		class Texture;
		using TextureRef = Effekseer::RefPtr<Texture>;
		class Texture : public Effekseer::Backend::Texture
		{
		private:
			bgfx_texture_handle_t buffer_{ BGFX_INVALID_HANDLE };
			//GraphicsDevice* graphicsDevice_ = nullptr;
			std::function<void()> onDisposed_;
			bool InitInternal(const Effekseer::Backend::TextureParameter& param);
		public:
			Texture(/*GraphicsDevice* graphicsDevice*/);
			~Texture() override;
			bool Init(const Effekseer::Backend::TextureParameter& param);
			bool Init(const Effekseer::Backend::RenderTextureParameter& param);
			bool Init(const Effekseer::Backend::DepthTextureParameter& param);
			bool Init(bgfx_texture_handle_t buffer, bool hasMipmap, const std::function<void()>& onDisposed);
			bgfx_texture_handle_t GetBuffer() const { return buffer_; }
		};

		class Model : public Effekseer::Model
		{
		public:
			Model(const Effekseer::CustomVector<Model::Vertex>& vertecies, const Effekseer::CustomVector<Model::Face>& faces);
			Model(const void* data, int32_t size);
			~Model();
		private:
			void create_buffer();
			friend class ModelLoader;
		};
	}
} // namespace EffekseerRendererBGFX
