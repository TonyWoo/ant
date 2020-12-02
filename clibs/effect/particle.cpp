#include "pch.h"
#include "particle.h"
#include "transforms.h"
#include "quadcache.h"

#include "random.h"

#define PARTICLE_COMPONENT		ID_count
#define PARTICLE_KEY_COMPONENT	ID_key_count
#include "psystem_manager.h"

extern bgfx_interface_vtbl_t* ibgfx();
#define BGFX(_API) ibgfx()->_API

particle_mgr::particle_mgr()
    : mmgr(particlesystem_create()){

	create_array<particles::life>();
	create_array<particles::spawn>();
	create_array<particles::velocity>();
	create_array<particles::acceleration>();
	create_array<particles::rendertype>();
	create_array<particles::uv_moitoin>();

	create_array<particles::init_life_interpolator>();
	create_array<particles::init_spawn_interpolator>();
	create_array<particles::init_velocity_interpolator>();
	create_array<particles::init_acceleration_interpolator>();
	create_array<particles::init_rendertype_interpolator>();
	create_array<particles::init_uv_motion_interpolator>();

	create_array<particles::lifetime_life_interpolator>();
	create_array<particles::lifetime_spawn_interpolator>();
	create_array<particles::lifetime_velocity_interpolator>();
	create_array<particles::lifetime_acceleration_interpolator>();
	create_array<particles::lifetime_rendertype_interpolator>();
	create_array<particles::lifetime_uv_motion_interpolator>();
}

class component_array {
public:
	virtual ~component_array() = default;
	virtual int remap(struct particle_remap* map, int n) = 0;
	virtual void pop_back() = 0;
};

particle_mgr::~particle_mgr(){
    particlesystem_release(mmgr);

	for(auto &a : mcomp_arrays){
		delete a;
		a = nullptr;
	}
}

template<typename T>
class component_array_baseT : public component_array {
public:
	component_id add(T &&v){
		mdata.push_back(std::move(v));
		return T::ID;
	}

	std::vector<T> mdata;

protected:
	template<typename COMP_ARRAY>
	static int remap(COMP_ARRAY *array, struct particle_remap *map, int n) {
		for (int i=0;i<n;i++) {
			if (map[i].component_id != map[0].component_id)
				return i;
			if (map[i].to_id != PARTICLE_INVALID) {
				array->move(map[i].from_id, map[i].to_id);
			} else {
				array->shrink(map[i].from_id);
			}
		}
		return n;
	}
};

template<typename T>
class component_arrayT : public component_array_baseT<T> {
public:
	virtual ~component_arrayT() = default;

	virtual int remap(struct particle_remap *map, int n) override{
		return component_array_baseT<T>::remap(this, map, n);
	}
	void move(int from, int to){
		this->mdata[from] = this->mdata[to];
	}

	void shrink(int n) {
		this->mdata.resize(n);
	}

	virtual void pop_back() override{
		this->mdata.pop_back();
	}
};

template<typename T>
class component_arrayT<T*> : public component_array_baseT<T*>{
public:
	virtual ~component_arrayT(){
		for (auto &p : this->mdata){
			delete p;
		}
	}

	virtual int remap(struct particle_remap *map, int n) override{
		return component_array_baseT<T*>::remap(this, map, n);
	}

	void move(int from, int to) {
		delete this->mdata[to];
		this->mdata[to] = this->mdata[from];
		this->mdata[from] = nullptr;
	}

	void shrink(int n) {
		for (int ii=n; ii<this->mdata.size(); ++ii){
			delete this->mdata[ii];
		}
		this->mdata.resize(n);
	}

	virtual void pop_back() override{
		delete this->mdata.back();
		this->mdata.pop_back();
	}
};

template<typename T>
void particle_mgr::create_array(){
	using TT = typename std::remove_pointer<T>::type;
	mcomp_arrays[TT::ID] = new component_arrayT<T>();
}

static inline bool
is_const_interp(int type){
	return type == 0;
}

static inline bool
is_linear_interp(int type){
	return type == 1;
}

static inline bool
is_curve_interp(int type){
	return type > 1;
}

template<typename T>
std::vector<T>& particle_mgr::data(){
	return static_cast<component_arrayT<T>*>(mcomp_arrays[T::ID])->mdata;
}

template<typename VALUE_TYPE>
static VALUE_TYPE
interp_vec(const VALUE_TYPE &scale, int type, randomobj &ro){
	VALUE_TYPE v;
	if (is_linear_interp(type)){
		for (uint32_t ii=0; ii<(uint32_t)scale.length(); ++ii){
			v[ii] = scale[ii] * particles::lifedata::MAX_PROCESS;
			const float random = ro();
			v[ii] *= random;
		}
	} else if (is_const_interp(type)){
		for (uint32_t ii=0; ii<(uint32_t)scale.length(); ++ii){
			v[ii] = scale[ii] * particles::lifedata::MAX_PROCESS;
		}
	}
	return v;
}

static uint32_t
interp_color(const glm::vec4 &scale, int type, randomobj &ro){
	glm::vec4 v = interp_vec(scale, type, ro);
	v *= 255.f;
	return uint32_t(uint8_t(v[0]) << 0|uint8_t(v[1]) << 8|uint8_t(v[2]) << 16 |uint8_t(v[3]) <<24);
}

void
particle_mgr::spawn_particles(float dt, uint32_t spawnidx, const particles::spawndata &sd){
	const float num_pre_second = float(sd.count) / sd.rate;

	const uint32_t spawnnum = uint32_t(dt * num_pre_second + 0.5f);

	if (spawnnum > 0){
		struct spawn_id{
			component_id id;
			particle_index idx;
		};
		const component_id init_ids[] = {
			// spawn init
			ID_init_life_interpolator,
			ID_init_velocity_interpolator,
			ID_init_acceleration_interpolator,
			ID_init_render_interpolator,
			
			// lifetime
			ID_lifetime_spawn_interpolator,
			ID_init_velocity_interpolator,
			ID_init_acceleration_interpolator,
			ID_init_render_interpolator,
		};

		std::vector<spawn_id>	particle_indices;

		//TODO: should be gloabl value
		std::unordered_map<component_id, std::function<component_id (uint32_t idx, randomobj &ro)>>	create_component_ops = {
			std::make_pair(ID_init_life_interpolator, [this](uint32_t idx, randomobj &ro){
				const auto &init_life_interpolator = data<particles::init_life_interpolator>();
				const auto& interp_life = init_life_interpolator[idx].comp;

				float life = interp_life.scale * particles::lifedata::MAX_PROCESS;
				if (is_linear_interp(interp_life.type))
					life *= ro();
				return add_component(particles::life{particles::lifedata(life)});
			}),

			std::make_pair(ID_init_velocity_interpolator, [this](uint32_t idx, randomobj &ro){
				const auto &c = data<particles::init_velocity_interpolator>()[idx].comp;
				return add_component(particles::velocity{interp_vec(c.scale, c.type, ro)});
			}),

			std::make_pair(ID_init_acceleration_interpolator, [this](uint32_t idx, randomobj &ro){
				const auto &c = data<particles::init_acceleration_interpolator>()[idx].comp;
				return add_component(particles::velocity{interp_vec(c.scale, c.type, ro)});
			}),

			std::make_pair(ID_init_render_interpolator, [this](uint32_t idx, randomobj &ro){
				const auto &init_render_interp = data<particles::init_rendertype_interpolator>();
				const auto &ri = init_render_interp[idx].comp;
				particles::renderdata rd;
				rd.s = interp_vec(ri.s.scale, ri.s.type, ro);
				rd.t = interp_vec(ri.t.scale, ri.s.type, ro);
				rd.color = interp_color(ri.color.scale, ri.color.type, ro);
				for(uint32_t ii=0; ii<4; ++ii){
					const auto &uv = ri.uv[ii];
					rd.uv[ii] = interp_vec(uv.scale, uv.type, ro);
				}

				return add_component(particles::rendertype{rd});
			}),
		};

		for (auto initid : init_ids){
			const particle_index idx = particlesystem_component(mmgr, ID_spawn, spawnidx, initid);
			if (PARTICLE_INVALID != idx)
				particle_indices.push_back(spawn_id{initid, idx});
		}

		randomobj ro;
		for (uint32_t ii=0; ii<spawnnum; ++ii){
			comp_ids ids;
			for (auto p : particle_indices){
				auto it = create_component_ops.find(p.id);
				if (it != create_component_ops.end()){
					ids.push_back(it->second(p.idx, ro));
				}
			}
		
			add(ids);
		}
	}
}

bool particle_mgr::add(const comp_ids &ids){
	const bool valid = 0 != particlesystem_add(mmgr, (int)ids.size(), (const int*)(&ids.front()));
	if (!valid)
		pop_back(ids);
	return valid;
}

void
particle_mgr::pop_back(const comp_ids &ids){
	for(auto id : ids){
		mcomp_arrays[id]->pop_back();
	}
}

void
particle_mgr::update_lifetime(float dt){
	auto &lifes = data<particles::life>();
	for (size_t ii=0; ii<lifes.size(); ++ii){
		auto &c = lifes[ii].comp;
		c.current += dt;
		if (c.update_process()){
			particlesystem_remove(mmgr, ID_life, (particle_index)ii);
		}
    }
}

void
particle_mgr::update_particle_spawn(float dt){
	const int n = particlesystem_count(mmgr, ID_TAG_emitter);
	for (int ii=0; ii<n; ++ii){
		const auto &sp = data<particles::spawn>()[ii].comp;
		const auto idx = particlesystem_component(mmgr, ID_TAG_emitter, ii, ID_spawn);
		spawn_particles(dt, idx, sp);
	}
}

void
particle_mgr::update_velocity(float dt){
	const auto &acc = data<particles::acceleration>();
	auto &vel = data<particles::velocity>();
	for (size_t aidx=0; aidx<acc.size(); ++aidx){
		const auto &a = acc[aidx].comp;
		auto vidx = particlesystem_component(mmgr, ID_acceleration, (particle_index)aidx, ID_velocity);
		assert(vidx < vel.size());
		auto &v = vel[vidx].comp;
		v += a * dt;
	}
}

void
particle_mgr::update_translation(float dt){
	const auto &vel = data<particles::velocity>();
	auto &render = data<particles::rendertype>();

	for (size_t vidx=0; vidx<vel.size(); ++vidx){
		const auto &v = vel[vidx].comp;
		auto tidx = particlesystem_component(mmgr, ID_velocity, (particle_index)vidx, ID_render);
		if (tidx != PARTICLE_INVALID){
			auto &r = render[vidx].comp;
			r.t += v * dt;
		}
	}
}

void
particle_mgr::update_uv_motion(float dt){
	const auto &uvmotion = data<particles::uv_moitoin>();
	const auto &rd = data<particles::rendertype>();

	for(int pidx=0; pidx<uvmotion.size(); ++pidx){
		const auto &uvm = uvmotion[pidx].comp;
		const auto ridx = particlesystem_component(mmgr, ID_uv_motion, pidx, ID_render);

		const uint32_t quadidx = rd[ridx].comp.quadidx;
		
		for (int ii=0; ii<4; ++ii){
			auto& v = quad_cache::get().get_vertex(quadidx, ii);
			v.uv.x += dt * uvm.u_speed * uvm.scale;
			v.uv.y += dt * uvm.v_speed * uvm.scale;
		}
	}
}

void
particle_mgr::update_quad_transform(float dt){
	for (const auto& r : data<particles::rendertype>()){
		const auto& c = r.comp;
		const uint32_t quadidx = c.quadidx;
		glm::mat4 m = glm::scale(c.s);
		m = glm::mat4(c.r) * m;
		m = glm::translate(c.t) * m;

		quad_cache::get().transform(quadidx, m);
		for (uint32_t ii=0; ii<4; ++ii){
			quad_cache::get().set_color(quadidx, ii, c.color);
			quad_cache::get().set_uv(quadidx, ii, c.uv[ii]);
		}
	}
}

void
particle_mgr::submit_render(){
	//TODO: quad_cache::submit() should call from lua update not here
	quad_cache::get().submit(0, (uint32_t)data<particles::rendertype>().size()); 
	quad_cache::get().update();
	BGFX(set_state(uint64_t(BGFX_STATE_WRITE_RGB|BGFX_STATE_WRITE_A|BGFX_STATE_DEPTH_TEST_ALWAYS|BGFX_STATE_BLEND_ALPHA|BGFX_STATE_MSAA), 0));

	for (size_t ii=0; ii<mrenderdata.textures.size(); ++ii){
		const auto &t = mrenderdata.textures[ii];
		BGFX(set_texture)((uint8_t)ii, {t.uniformid}, {t.texid}, UINT16_MAX);
	}
	
	BGFX(submit)(mrenderdata.viewid, {mrenderdata.progid}, 0, BGFX_DISCARD_ALL);
}

void
particle_mgr::recap_particles(){
    struct particle_remap remap[128];
	struct particle_arrange_context ctx;
	int cap = sizeof(remap)/sizeof(remap[0]);
	int n;
	do {
		n = particlesystem_arrange(mmgr, cap, remap, &ctx);
		int i = 0;
		while (i < n) {
			int component_id = remap[i].component_id;
			if (component_id < ID_key_count) {
				i += mcomp_arrays[component_id]->remap(remap + i, n - i);
			}
			else {
				++i;
			}
		}
	} while (n == cap);
}

void
particle_mgr::update(float dt){
	update_lifetime(dt);
	update_velocity(dt);
	update_translation(dt);
	update_uv_motion(dt);

	update_quad_transform(dt);
	recap_particles();

	//TODO: we can fully control render in lua level, only need vertex buffer in quad_cache
	submit_render();
}
