#include "PMFXYZ.h"
#include "ScopedGILRelease.h"

#include <stdexcept>
#ifdef __SSE2__
#include <emmintrin.h>
#endif

#ifdef ENABLE_OPENMP
#include <omp.h>
#endif

#include <tbb/tbb.h>

#include "VectorMath.h"

using namespace std;
using namespace boost::python;

using namespace tbb;

/*! \internal
    \file PMFXYZ.cc
    \brief Routines for computing 3D anisotropic potential of mean force
*/

namespace freud { namespace pmft {

PMFXYZ::PMFXYZ(const trajectory::Box& box, float max_x, float max_y, float max_z, float dx, float dy, float dz)
    : m_box(box), m_max_x(max_x), m_max_y(max_y), m_max_z(max_z), m_dx(dx), m_dy(dy), m_dz(dz)
    {
    if (dx < 0.0f)
        throw invalid_argument("dx must be positive");
    if (dy < 0.0f)
        throw invalid_argument("dy must be positive");
    if (dz < 0.0f)
        throw invalid_argument("dz must be positive");
    if (max_x < 0.0f)
        throw invalid_argument("max_x must be positive");
    if (max_y < 0.0f)
        throw invalid_argument("max_y must be positive");
    if (max_z < 0.0f)
        throw invalid_argument("max_z must be positive");
    if (dx > max_x)
        throw invalid_argument("max_x must be greater than dx");
    if (dy > max_y)
        throw invalid_argument("max_y must be greater than dy");
    if (dz > max_z)
        throw invalid_argument("max_z must be greater than dz");
    if (max_x > box.getLx()/2 || max_y > box.getLy()/2)
        throw invalid_argument("max_x, max_y must be smaller than half the smallest box size");
    if (max_z > box.getLz()/2 && !box.is2D())
        throw invalid_argument("max_z must be smaller than half the smallest box size");

    m_nbins_x = int(2 * floorf(m_max_x / m_dx));
    assert(m_nbins_x > 0);
    m_nbins_y = int(2 * floorf(m_max_y / m_dy));
    assert(m_nbins_y > 0);
    m_nbins_z = int(2 * floorf(m_max_z / m_dz));
    assert(m_nbins_z > 0);

    // precompute the bin center positions for x
    m_x_array = boost::shared_array<float>(new float[m_nbins_x]);
    for (unsigned int i = 0; i < m_nbins_x; i++)
        {
        float x = float(i) * m_dx;
        float nextx = float(i+1) * m_dx;
        m_x_array[i] = -m_max_x + ((x + nextx) / 2.0);
        }

    // precompute the bin center positions for y
    m_y_array = boost::shared_array<float>(new float[m_nbins_y]);
    for (unsigned int i = 0; i < m_nbins_y; i++)
        {
        float y = float(i) * m_dy;
        float nexty = float(i+1) * m_dy;
        m_y_array[i] = -m_max_y + ((y + nexty) / 2.0);
        }

    // precompute the bin center positions for z
    m_z_array = boost::shared_array<float>(new float[m_nbins_z]);
    for (unsigned int i = 0; i < m_nbins_z; i++)
        {
        float z = float(i) * m_dz;
        float nextz = float(i+1) * m_dz;
        m_z_array[i] = -m_max_z + ((z + nextz) / 2.0);
        }

    // create and populate the pcf_array
    m_pcf_array = boost::shared_array<unsigned int>(new unsigned int[m_nbins_x * m_nbins_y * m_nbins_z]);
    memset((void*)m_pcf_array.get(), 0, sizeof(unsigned int)*m_nbins_x*m_nbins_y*m_nbins_z);

    if (useCells())
        {
        float max_val = sqrtf(max_x*max_x + max_y*max_y + max_z*max_z);
        m_lc = new locality::LinkCell(box, max_val);
        }
    }

PMFXYZ::~PMFXYZ()
    {
    if(useCells())
    delete m_lc;
    }

//! \internal
/*! \brief Helper class to compute PMF in parallel without the cell list
*/

class ComputePMFTWithoutCellList
    {
    private:
        atomic<unsigned int> *m_pcf_array;
        unsigned int m_nbins_x;
        unsigned int m_nbins_y;
        unsigned int m_nbins_z;
        const trajectory::Box m_box;
        const float m_max_x;
        const float m_max_y;
        const float m_max_z;
        const float m_dx;
        const float m_dy;
        const float m_dz;
        const float3 *m_ref_points;
        const float4 *m_ref_orientations;
        const unsigned int m_Nref;
        const float3 *m_points;
        const float4 *m_orientations;
        const unsigned int m_Np;
        const float4 *m_extra_orientations;
    public:
        ComputePMFTWithoutCellList(atomic<unsigned int> *pcf_array,
                                   unsigned int nbins_x,
                                   unsigned int nbins_y,
                                   unsigned int nbins_z,
                                   const trajectory::Box &box,
                                   const float max_x,
                                   const float max_y,
                                   const float max_z,
                                   const float dx,
                                   const float dy,
                                   const float dz,
                                   const float3 *ref_points,
                                   const float4 *ref_orientations,
                                   unsigned int Nref,
                                   const float3 *points,
                                   const float4 *orientations,
                                   unsigned int Np,
                                   const float4 *extra_orientations)
            : m_pcf_array(pcf_array), m_nbins_x(nbins_x), m_nbins_y(nbins_y), m_nbins_z(nbins_z), m_box(box),
              m_max_x(max_x), m_max_y(max_y), m_max_z(max_z), m_dx(dx), m_dy(dy), m_dz(dz), m_ref_points(ref_points),
              m_ref_orientations(ref_orientations), m_Nref(Nref), m_points(points), m_orientations(orientations), m_Np(Np),
              m_extra_orientations(extra_orientations)
        {
        }
        void operator()( const blocked_range<size_t> &myR ) const
            {
            assert(m_ref_points);
            assert(m_points);
            assert(m_Nref > 0);
            assert(m_Np > 0);

            // precalc some values for faster computation within the loop
            float dx_inv = 1.0f / m_dx;
            float maxxsq = m_max_x * m_max_x;
            float dy_inv = 1.0f / m_dy;
            float maxysq = m_max_y * m_max_y;
            float dz_inv = 1.0f / m_dz;
            float maxzsq = m_max_z * m_max_z;

            // for each reference point
            for (size_t i = myR.begin(); i != myR.end(); i++)
                {
                float3 ref = m_ref_points[i];
                // for each point to check
                for (unsigned int j = 0; j < m_Np; j++)
                    {
                    float3 point = m_points[j];
                    // compute r between the two particles
                    float dx = float(ref.x - point.x);
                    float dy = float(ref.y - point.y);
                    float dz = float(ref.z - point.z);

                    // make sure that the particles are wrapped into the box
                    float3 delta = m_box.wrap(make_float3(dx, dy, dz));

                    // check that the particle is not checking itself
                    // 1e-6 is an arbitrary value that could be set differently if needed
                    float xsq = delta.x*delta.x;
                    float ysq = delta.y*delta.y;
                    float zsq = delta.z*delta.z;
                    if ((xsq < 1e-6) && (ysq < 1e-6) && (zsq < 1e-6))
                        {
                        // skip if the same particle
                        continue;
                        }
                    float x = delta.x;
                    float y = delta.y;
                    float z = delta.z;

                    // rotate interparticle vector
                    quat<float> q(m_ref_orientations[i].w,
                                  vec3<float>(m_ref_orientations[i].x,
                                              m_ref_orientations[i].y,
                                              m_ref_orientations[i].z));
                    // create the extra quaternion
                    quat<float> qe(m_extra_orientations[i].w,
                                  vec3<float>(m_extra_orientations[i].x,
                                              m_extra_orientations[i].y,
                                              m_extra_orientations[i].z));
                    vec3<float> v(x, y, z);
                    v = rotate(conj(q), v);
                    v = rotate(qe, v);

                    x = v.x + m_max_x;
                    y = v.y + m_max_y;
                    z = v.z + m_max_z;

                    // bin that point
                    float binx = floorf(x * dx_inv);
                    float biny = floorf(y * dy_inv);
                    float binz = floorf(z * dz_inv);
                    // fast float to int conversion with truncation
                    #ifdef __SSE2__
                    unsigned int ibinx = _mm_cvtt_ss2si(_mm_load_ss(&binx));
                    unsigned int ibiny = _mm_cvtt_ss2si(_mm_load_ss(&biny));
                    unsigned int ibinz = _mm_cvtt_ss2si(_mm_load_ss(&binz));
                    #else
                    unsigned int ibinx = (unsigned int)(binx);
                    unsigned int ibiny = (unsigned int)(biny);
                    unsigned int ibinz = (unsigned int)(binz);
                    #endif

                    // increment the bin; this is handled by atomic operations
                    if ((ibinx < m_nbins_x) && (ibiny < m_nbins_y) && (ibinz < m_nbins_z))
                        {
                        m_pcf_array[ibinz*m_nbins_y*m_nbins_x + ibiny*m_nbins_x + ibinx]++;
                        }
                    }
                } // done looping over reference points
            }
    };

//! \internal
/*! \brief Helper class to compute PMF in parallel with the cell list
*/
class ComputePMFTWithCellList
    {
    private:
        atomic<unsigned int> *m_pcf_array;
        unsigned int m_nbins_x;
        unsigned int m_nbins_y;
        unsigned int m_nbins_z;
        const trajectory::Box m_box;
        const float m_max_x;
        const float m_max_y;
        const float m_max_z;
        const float m_dx;
        const float m_dy;
        const float m_dz;
        const locality::LinkCell *m_lc;
        const float3 *m_ref_points;
        const float4 *m_ref_orientations;
        const unsigned int m_Nref;
        const float3 *m_points;
        const float4 *m_orientations;
        const unsigned int m_Np;
        const float4 *m_extra_orientations;
    public:
        ComputePMFTWithCellList(atomic<unsigned int> *pcf_array,
                               unsigned int nbins_x,
                               unsigned int nbins_y,
                               unsigned int nbins_z,
                               const trajectory::Box &box,
                               const float max_x,
                               const float max_y,
                               const float max_z,
                               const float dx,
                               const float dy,
                               const float dz,
                               const locality::LinkCell *lc,
                               const float3 *ref_points,
                               const float4 *ref_orientations,
                               unsigned int Nref,
                               const float3 *points,
                               const float4 *orientations,
                               unsigned int Np,
                               const float4 *extra_orientations)
            : m_pcf_array(pcf_array), m_nbins_x(nbins_x), m_nbins_y(nbins_y), m_nbins_z(nbins_z), m_box(box),
              m_max_x(max_x), m_max_y(max_y), m_max_z(max_z), m_dx(dx), m_dy(dy), m_dz(dz), m_lc(lc),
              m_ref_points(ref_points), m_ref_orientations(ref_orientations), m_Nref(Nref), m_points(points),
              m_orientations(orientations), m_Np(Np), m_extra_orientations(extra_orientations)
        {
        }
        void operator()( const blocked_range<size_t> &myR ) const
            {
            assert(m_ref_points);
            assert(m_points);
            assert(m_Nref > 0);
            assert(m_Np > 0);

            // precalc some values for faster computation within the loop
            float dx_inv = 1.0f / m_dx;
            float maxxsq = m_max_x * m_max_x;
            float dy_inv = 1.0f / m_dy;
            float maxysq = m_max_y * m_max_y;
            float dz_inv = 1.0f / m_dz;
            float maxzsq = m_max_z * m_max_z;

            // for each reference point
            for (size_t i = myR.begin(); i != myR.end(); i++)
                {
                // get the cell the point is in
                float3 ref = m_ref_points[i];
                unsigned int ref_cell = m_lc->getCell(ref);

                // loop over all neighboring cells
                const std::vector<unsigned int>& neigh_cells = m_lc->getCellNeighbors(ref_cell);
                for (unsigned int neigh_idx = 0; neigh_idx < neigh_cells.size(); neigh_idx++)
                    {
                    unsigned int neigh_cell = neigh_cells[neigh_idx];

                    // iterate over the particles in that cell
                    locality::LinkCell::iteratorcell it = m_lc->itercell(neigh_cell);
                    for (unsigned int j = it.next(); !it.atEnd(); j=it.next())
                        {
                        // compute r between the two particles
                        float3 point = m_points[j];
                        float dx = float(ref.x - point.x);
                        float dy = float(ref.y - point.y);
                        float dz = float(ref.z - point.z);

                        // make sure that the particles are wrapped into the box
                        float3 delta = m_box.wrap(make_float3(dx, dy, dz));

                        // check that the particle is not checking itself
                        // 1e-6 is an arbitrary value that could be set differently if needed
                        float xsq = delta.x*delta.x;
                        float ysq = delta.y*delta.y;
                        float zsq = delta.z*delta.z;
                        if ((xsq < 1e-6) && (ysq < 1e-6) && (zsq < 1e-6))
                            {
                            continue;
                            }
                        float x = delta.x;
                        float y = delta.y;
                        float z = delta.z;

                        // rotate interparticle vector

                        // create the reference point quaternion
                        quat<float> q(m_ref_orientations[i].w,
                                      vec3<float>(m_ref_orientations[i].x,
                                                  m_ref_orientations[i].y,
                                                  m_ref_orientations[i].z));
                        // create the extra quaternion
                        quat<float> qe(m_extra_orientations[i].w,
                                      vec3<float>(m_extra_orientations[i].x,
                                                  m_extra_orientations[i].y,
                                                  m_extra_orientations[i].z));
                        // create point vector
                        vec3<float> v(x, y, z);
                        // rotate the vector
                        v = rotate(conj(q), v);
                        v = rotate(qe, v);

                        x = v.x + m_max_x;
                        y = v.y + m_max_y;
                        z = v.z + m_max_z;

                        // bin that point
                        float binx = floorf(x * dx_inv);
                        float biny = floorf(y * dy_inv);
                        float binz = floorf(z * dz_inv);
                        // fast float to int conversion with truncation
                        #ifdef __SSE2__
                        unsigned int ibinx = _mm_cvtt_ss2si(_mm_load_ss(&binx));
                        unsigned int ibiny = _mm_cvtt_ss2si(_mm_load_ss(&biny));
                        unsigned int ibinz = _mm_cvtt_ss2si(_mm_load_ss(&binz));
                        #else
                        unsigned int ibinx = (unsigned int)(binx);
                        unsigned int ibiny = (unsigned int)(biny);
                        unsigned int ibinz = (unsigned int)(binz);
                        #endif

                        // increment the bin; this is handled by atomic operations
                        // it is possible that this is better handled by an array of atomics...
                        if ((ibinx < m_nbins_x) && (ibiny < m_nbins_y) && (ibinz < m_nbins_z))
                            {
                            m_pcf_array[ibinz*m_nbins_y*m_nbins_x + ibiny*m_nbins_x + ibinx]++;
                            }
                        }
                    }
                } // done looping over reference points
            }
    };

//! \internal
/*! \brief Function to determine if the cell list should be used or not
*/

bool PMFXYZ::useCells()
    {
    float l_min = fmin(m_box.getLx(), m_box.getLy());

    if (!m_box.is2D())
        l_min = fmin(l_min, m_box.getLz());

    float rmax = sqrtf(m_max_x*m_max_x + m_max_y*m_max_y + m_max_z*m_max_z);

    if (rmax < l_min/3.0f)
        return true;

    return false;
    }

//! \internal
/*! \brief Function to reset the pcf array if needed e.g. calculating between new particle types
*/

void PMFXYZ::resetPCF()
    {
    memset((void*)m_pcf_array.get(), 0, sizeof(unsigned int)*m_nbins_x*m_nbins_y*m_nbins_z);
    }

//! \internal
/*! \brief Helper functionto direct the calculation to the correct helper class
*/

void PMFXYZ::compute(const float3 *ref_points,
                      const float4 *ref_orientations,
                      unsigned int Nref,
                      const float3 *points,
                      const float4 *orientations,
                      unsigned int Np,
                      const float4 *extra_orientations)
    {
    if (useCells())
        {
        m_lc->computeCellList(points, Np);
        parallel_for(blocked_range<size_t>(0,Nref), ComputePMFTWithCellList((atomic<unsigned int>*)m_pcf_array.get(),
                                                                            m_nbins_x,
                                                                            m_nbins_y,
                                                                            m_nbins_z,
                                                                            m_box,
                                                                            m_max_x,
                                                                            m_max_y,
                                                                            m_max_z,
                                                                            m_dx,
                                                                            m_dy,
                                                                            m_dz,
                                                                            m_lc,
                                                                            ref_points,
                                                                            ref_orientations,
                                                                            Nref,
                                                                            points,
                                                                            orientations,
                                                                            Np,
                                                                            extra_orientations));
        }
    else
        {
        parallel_for(blocked_range<size_t>(0,Nref), ComputePMFTWithoutCellList((atomic<unsigned int>*)m_pcf_array.get(),
                                                                               m_nbins_x,
                                                                               m_nbins_y,
                                                                               m_nbins_z,
                                                                               m_box,
                                                                               m_max_x,
                                                                               m_max_y,
                                                                               m_max_z,
                                                                               m_dx,
                                                                               m_dy,
                                                                               m_dz,
                                                                               ref_points,
                                                                               ref_orientations,
                                                                               Nref,
                                                                               points,
                                                                               orientations,
                                                                               Np,
                                                                               extra_orientations));
        }
    }

//! \internal
/*! \brief Exposed function to python to calculate the PMF
*/

void PMFXYZ::computePy(boost::python::numeric::array ref_points,
                        boost::python::numeric::array ref_orientations,
                        boost::python::numeric::array points,
                        boost::python::numeric::array orientations,
                        boost::python::numeric::array extra_orientations)
    {
    // validate input type and rank
    num_util::check_type(ref_points, PyArray_FLOAT);
    num_util::check_rank(ref_points, 2);
    num_util::check_type(ref_orientations, PyArray_FLOAT);
    num_util::check_rank(ref_orientations, 2);
    num_util::check_type(points, PyArray_FLOAT);
    num_util::check_rank(points, 2);
    num_util::check_type(orientations, PyArray_FLOAT);
    num_util::check_rank(orientations, 2);
    num_util::check_type(extra_orientations, PyArray_FLOAT);
    num_util::check_rank(extra_orientations, 2);

    // validate that the 2nd dimension is only 3
    num_util::check_dim(points, 1, 3);
    unsigned int Np = num_util::shape(points)[0];

    num_util::check_dim(ref_points, 1, 3);
    unsigned int Nref = num_util::shape(ref_points)[0];

    // check the size of angles to be correct
    num_util::check_dim(ref_orientations, 0, Nref);
    num_util::check_dim(ref_orientations, 1, 4);
    num_util::check_dim(orientations, 0, Np);
    num_util::check_dim(orientations, 1, 4);
    num_util::check_dim(extra_orientations, 0, Nref);
    num_util::check_dim(extra_orientations, 1, 4);

    // get the raw data pointers and compute the cell list
    float3* ref_points_raw = (float3*) num_util::data(ref_points);
    float4* ref_orientations_raw = (float4*) num_util::data(ref_orientations);
    float3* points_raw = (float3*) num_util::data(points);
    float4* orientations_raw = (float4*) num_util::data(orientations);
    float4* extra_orientations_raw = (float4*) num_util::data(extra_orientations);

        // compute with the GIL released
        {
        util::ScopedGILRelease gil;
        compute(ref_points_raw, ref_orientations_raw, Nref, points_raw, orientations_raw, Np, extra_orientations_raw);
        }
    }

void export_PMFXYZ()
    {
    class_<PMFXYZ>("PMFXYZ", init<trajectory::Box&, float, float, float, float, float, float>())
        .def("getBox", &PMFXYZ::getBox, return_internal_reference<>())
        .def("compute", &PMFXYZ::computePy)
        .def("getPCF", &PMFXYZ::getPCFPy)
        .def("getX", &PMFXYZ::getXPy)
        .def("getY", &PMFXYZ::getYPy)
        .def("getZ", &PMFXYZ::getZPy)
        ;
    }

}; }; // end namespace freud::pmft