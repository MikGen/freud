
from freud.util._VectorMath cimport vec3
from freud.util._VectorMath cimport quat
from freud.util._Boost cimport shared_array
cimport freud._trajectory as _trajectory
cimport freud._order as order
from libc.string cimport memcpy
from libcpp.complex cimport complex
from libcpp.vector cimport vector
from libcpp.map cimport map
from libcpp.pair cimport pair
import numpy as np
cimport numpy as np
from cython.view cimport array as cvarray
import time

# Numpy must be initialized. When using numpy from C or Cython you must
# _always_ do that, or you will have segfaults
np.import_array()

cdef class BondOrder:
    """Compute the bond order diagram for the system of particles.

    Create the 2D histogram containing the number of bonds formed through the surface of a unit sphere based on the
    equatorial (Theta) and azimuthal (Phi) *check on this* angles.

    .. note:: currently being debugged. not guaranteed to work.

    :param r_max: distance over which to calculate
    :param k: order parameter i. to be removed
    :param n: number of neighbors to find
    :param nBinsT: number of theta bins
    :param nBinsP: number of phi bins
    :type r_max: float
    :type k: unsigned int
    :type n: unsigned int
    :type nBinsT: unsigned int
    :type nBinsP: unsigned int

    .. todo:: remove k, it is not used as such
    """
    cdef order.BondOrder *thisptr

    def __cinit__(self, rmax, k, n, nBinsT, nBinsP):
        self.thisptr = new order.BondOrder(rmax, k, n, nBinsT, nBinsP)

    def __dealloc__(self):
        del self.thisptr

    def accumulate(self, box, refPoints, refOrientations, points, orientations):
        """
        Calculates the correlation function and adds to the current histogram.

        :param box: simulation box
        :param refPoints: reference points to calculate the local density
        :param refOrientations: orientations to use in computation
        :param points: points to calculate the local density
        :param orientations: orientations to use in computation
        :type box: :py:meth:`freud.trajectory.Box`
        :type refPoints: np.float32
        :type refOrientations: np.float32
        :type points: np.float32
        :type orientations: np.float32
        """
        if (refPoints.dtype != np.float32) or (points.dtype != np.float32):
            raise ValueError("points must be a numpy float32 array")
        if refPoints.ndim != 2 or points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if refPoints.shape[1] != 3 or points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        if (refOrientations.dtype != np.float32) or (orientations.dtype != np.float32):
            raise ValueError("values must be a numpy float32 array")
        if refOrientations.ndim != 2 or orientations.ndim != 2:
            raise ValueError("values must be a 1 dimensional array")
        if refOrientations.shape[1] != 4 or orientations.shape[1] != 4:
            raise ValueError("the 2nd dimension must have 3 values: q0, q1, q2, q3")
        cdef np.ndarray[float, ndim=1] l_refPoints = np.ascontiguousarray(refPoints.flatten())
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef np.ndarray[float, ndim=1] l_refOrientations = np.ascontiguousarray(refOrientations.flatten())
        cdef np.ndarray[float, ndim=1] l_orientations = np.ascontiguousarray(orientations.flatten())
        cdef unsigned int nRef = <unsigned int> refPoints.shape[0]
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        with nogil:
            self.thisptr.accumulate(l_box, <vec3[float]*>&l_refPoints[0], <quat[float]*>&l_refOrientations[0], nRef, <vec3[float]*>&l_points[0], <quat[float]*>&l_orientations[0], nP)

    def getBondOrder(self):
        """
        :return: bond order
        :rtype: np.float32
        """
        cdef float *bod = self.thisptr.getBondOrder().get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp>self.thisptr.getNBinsPhi()
        nbins[1] = <np.npy_intp>self.thisptr.getNBinsTheta()
        cdef np.ndarray[float, ndim=2] result = np.PyArray_SimpleNewFromData(2, nbins, np.NPY_FLOAT32, <void*>bod)
        return result

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def resetBondOrder(self):
        """
        resets the values of the bond order in memory
        """
        self.thisptr.resetBondOrder()

    def compute(self, box, refPoints, refOrientations, points, orientations):
        """
        Calculates the bond order histogram. Will overwrite the current histogram.

        :param box: simulation box
        :param refPoints: reference points to calculate the local density
        :param refOrientations: orientations to use in computation
        :param points: points to calculate the local density
        :param orientations: orientations to use in computation
        :type box: :py:meth:`freud.trajectory.Box`
        :type refPoints: np.float32
        :type refOrientations: np.float32
        :type points: np.float32
        :type orientations: np.float32
        """
        self.thisptr.resetBondOrder()
        self.accumulate(box, refPoints, refOrientations, points, orientations)

    def reduceBondOrder(self):
        """
        Reduces the histogram in the values over N processors to a single histogram. This is called automatically by
        :py:meth:`freud.order.BondOrder.getBondOrder()`.
        """
        self.thisptr.reduceBondOrder()

    def getTheta(self):
        """
        :return: values of bin centers for Theta
        :rtype: np.float32
        """
        cdef float *theta = self.thisptr.getTheta().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNBinsTheta()
        cdef np.ndarray[np.float32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>theta)
        return result

    def getPhi(self):
        """
        :return: values of bin centers for Phi
        :rtype: np.float32
        """
        cdef float *phi = self.thisptr.getPhi().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNBinsPhi()
        cdef np.ndarray[np.float32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>phi)
        return result

    def getNBinsTheta(self):
        """
        Get the number of bins in the Theta-dimension of histogram

        :return: nTheta
        :rtype: unsigned int
        """
        cdef unsigned int nt = self.thisptr.getNBinsTheta()
        return nt

    def getNBinsPhi(self):
        """
        Get the number of bins in the Phi-dimension of histogram

        :return: nPhi
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNBinsPhi()
        return np

cdef class CubaticOrderParameter:
    """Compute the Cubatic Order Parameter [Cit1]_ for a system of particles using simulated annealing instead of \
    Newton-Raphson root finding.

    :param t_initial: Starting temperature
    :param t_final: Final temperature
    :param scale: Scaling factor to reduce temperature
    :param n_replicates: Number of replicate simulated annealing runs
    :param seed: random seed to use in calculations. If None, system time used
    :type t_initial: float
    :type t_final: float
    :type scale: float
    :type n_replicates: unsigned int
    :type seed: unsigned int

    """
    cdef order.CubaticOrderParameter *thisptr

    def __cinit__(self, t_initial, t_final, scale, n_replicates=1, seed=None):
        # run checks
        if (t_final >= t_initial):
            raise ValueError("t_final must be less than t_initial")
        if (scale >= 1.0):
            raise ValueError("scale must be less than 1")
        if seed is None:
            seed = int(time.time())
        elif not isinstance(seed, int):
            try:
                seed = int(seed)
            finally:
                print("supplied seed could not be used. using time as seed")
                seed = time.time()

        # for c++ code
        # create generalized rank four tensor, pass into c++
        cdef np.ndarray[float, ndim=2] kd = np.eye(3, dtype=np.float32)
        cdef np.ndarray[float, ndim=4] dijkl = np.einsum("ij,kl->ijkl", kd, kd, dtype=np.float32)
        cdef np.ndarray[float, ndim=4] dikjl = np.einsum("ik,jl->ijkl", kd, kd, dtype=np.float32)
        cdef np.ndarray[float, ndim=4] diljk = np.einsum("il,jk->ijkl", kd, kd, dtype=np.float32)
        cdef np.ndarray[float, ndim=4] r4 = dijkl+dikjl+diljk
        r4 *= (2.0/5.0)
        self.thisptr = new order.CubaticOrderParameter(t_initial, t_final, scale, <float*>r4.data, n_replicates, seed)

    def compute(self, orientations):
        """
        Calculates the per-particle and global OP

        :param box: simulation box
        :param orientations: orientations to calculate the order parameter
        :type box: :py:meth:`freud.trajectory.Box`
        :type orientations: np.float32
        """
        if (orientations.dtype != np.float32):
            raise ValueError("orientations must be a numpy float32 array")
        if orientations.ndim != 2:
            raise ValueError("orientations must be a 2 dimensional array")
        if orientations.shape[1] != 4:
            raise ValueError("the 2nd dimension must have 4 values: q0, q1, q2, q3")
        cdef np.ndarray[float, ndim=2] l_orientations = orientations
        cdef unsigned int num_particles = <unsigned int> orientations.shape[0]

        with nogil:
            self.thisptr.compute(<quat[float]*>l_orientations.data, num_particles, 1)

    def get_t_initial(self):
        """
        :return: value of initial temperature
        :rtype: float
        """
        return self.thisptr.getTInitial()

    def get_t_final(self):
        """
        :return: value of final temperature
        :rtype: float
        """
        return self.thisptr.getTFinal()

    def get_scale(self):
        """
        :return: value of scale
        :rtype: float
        """
        return self.thisptr.getScale()

    def get_cubatic_order_parameter(self):
        """
        :return: Cubatic Order parameter
        :rtype: float
        """
        return self.thisptr.getCubaticOrderParameter()

    def get_orientation(self):
        """
        :return: orientation of global orientation
        :rtype: np.float32
        """
        cdef quat[float] q = self.thisptr.getCubaticOrientation()
        cdef np.npy_intp nbins[1]
        nbins[0] = 4
        # This should be updated/changed at some point
        # cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>&qij)
        cdef np.ndarray[float, ndim=1] result = np.array([q.s, q.v.x, q.v.y, q.v.z], dtype=np.float32)
        return result

    def get_particle_op(self):
        """
        :return: Cubatic Order parameter
        :rtype: float
        """
        cdef float * particle_op = self.thisptr.getParticleCubaticOrderParameter().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNumParticles()
        cdef np.ndarray[np.float32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32,<void*>particle_op)
        return result

    def get_particle_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle orientation
        :rtype: np.float32
        """
        cdef float *particle_tensor = self.thisptr.getParticleTensor().get()
        cdef np.npy_intp nbins[5]
        nbins[0] = <np.npy_intp>self.thisptr.getNumParticles()
        nbins[1] = <np.npy_intp>3
        nbins[2] = <np.npy_intp>3
        nbins[3] = <np.npy_intp>3
        nbins[4] = <np.npy_intp>3
        cdef np.ndarray[np.float32_t, ndim=5] result = np.PyArray_SimpleNewFromData(5, nbins, np.NPY_FLOAT32, <void*>particle_tensor)
        return result

    def get_global_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle orientation
        :rtype: np.float32
        """
        cdef float *global_tensor = self.thisptr.getGlobalTensor().get()
        cdef np.npy_intp nbins[4]
        nbins[0] = <np.npy_intp>3
        nbins[1] = <np.npy_intp>3
        nbins[2] = <np.npy_intp>3
        nbins[3] = <np.npy_intp>3
        cdef np.ndarray[np.float32_t, ndim=4] result = np.PyArray_SimpleNewFromData(4, nbins, np.NPY_FLOAT32, <void*>global_tensor)
        return result

    def get_cubatic_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle orientation
        :rtype: np.float32
        """
        cdef float *cubatic_tensor = self.thisptr.getCubaticTensor().get()
        cdef np.npy_intp nbins[4]
        nbins[0] = <np.npy_intp>3
        nbins[1] = <np.npy_intp>3
        nbins[2] = <np.npy_intp>3
        nbins[3] = <np.npy_intp>3
        cdef np.ndarray[np.float32_t, ndim=4] result = np.PyArray_SimpleNewFromData(4, nbins, np.NPY_FLOAT32, <void*>cubatic_tensor)
        return result

    def get_gen_r4_tensor(self):
        """
        :return: Rank 4 tensor corresponding to each individual particle orientation
        :rtype: np.float32
        """
        cdef float *gen_r4_tensor = self.thisptr.getGenR4Tensor().get()
        cdef np.npy_intp nbins[4]
        nbins[0] = <np.npy_intp>3
        nbins[1] = <np.npy_intp>3
        nbins[2] = <np.npy_intp>3
        nbins[3] = <np.npy_intp>3
        cdef np.ndarray[np.float32_t, ndim=4] result = np.PyArray_SimpleNewFromData(4, nbins, np.NPY_FLOAT32, <void*>gen_r4_tensor)
        return result

cdef class EntropicBonding:
    """Compute the entropic bonds each particle in the system.

    For each particle in the system determine which other particles are in which entropic bonding sites.

    .. note:: currently being debugged. not guaranteed to work.

    :param xmax: +/- x distance to search for bonds
    :param ymax: +/- y distance to search for bonds
    :param nx: number of bins in x
    :param ny: number of bins in x
    :param nNeighbors: number of neighbors to find
    :param nBonds: number of bonds to populate per particle
    :param bondMap: 2D array containing the bond index for each x, y coordinate
    :type xmax: float
    :type ymax: float
    :type nx: unsigned int
    :type ny: unsigned int
    :type nNeighbors: unsigned int
    :type nBonds: unsigned int
    """
    cdef order.EntropicBonding *thisptr

    def __cinit__(self, xmax, ymax, nx, ny, nNeighbors, nBonds, bondMap):
        # should I extract from the bond map (nx, ny)
        cdef np.ndarray[unsigned int, ndim=1] l_bondMap = np.ascontiguousarray(bondMap.flatten())
        self.thisptr = new order.EntropicBonding(xmax, ymax, nx, ny, nNeighbors, nBonds, <unsigned int*>&l_bondMap[0])

    def __dealloc__(self):
        del self.thisptr

    def compute(self, box, points, orientations):
        """
        Calculates the correlation function and adds to the current histogram.

        :param box: simulation box
        :param points: points to calculate the bonding
        :param orientations: orientations as angles to use in computation
        :type box: :py:meth:`freud.trajectory.Box`
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        :type orientations: np.ndarray(shape=(N), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        if orientations.dtype != np.float32:
            raise ValueError("values must be a numpy float32 array")
        if orientations.ndim != 1:
            raise ValueError("values must be a 1 dimensional array")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef np.ndarray[float, ndim=1] l_orientations = np.ascontiguousarray(orientations.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        with nogil:
            self.thisptr.compute(l_box, <vec3[float]*>&l_points[0], <float*>&l_orientations[0], nP)

    def getBonds(self):
        """
        :return: particle bonds
        :rtype: np.float32
        """
        cdef unsigned int *bonds = self.thisptr.getBonds().get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp>self.thisptr.getNBinsY()
        nbins[1] = <np.npy_intp>self.thisptr.getNBinsX()
        cdef np.ndarray[float, ndim=2] result = np.PyArray_SimpleNewFromData(2, nbins, np.NPY_FLOAT32, <void*>bonds)
        return result

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def getNBinsX(self):
        """
        Get the number of bins in the x-dimension of histogram

        :return: nx
        :rtype: unsigned int
        """
        cdef unsigned int nx = self.thisptr.getNBinsX()
        return nx

    def getNBinsY(self):
        """
        Get the number of bins in the y-dimension of histogram

        :return: ny
        :rtype: unsigned int
        """
        cdef unsigned int ny = self.thisptr.getNBinsY()
        return ny

cdef class HexOrderParameter:
    """Calculates the x-atic order parameter for each particle in the system.

    The x-atic order parameter for a particle :math:`i` and its :math:`n` neighbors :math:`j` is given by:

    :math:`\\psi_k \\left( i \\right) = \\frac{1}{n} \\sum_j^n e^{k i \\phi_{ij}}`

    The parameter :math:`k` governs the symmetry of the order parameter while the parameter :math:`n` governs the number \
    of neighbors of particle :math:`i` to average over. :math:`\\phi_{ij}` is the angle between the vector \
     :math:`r_{ij}` and :math:`\\left( 1,0 \\right)`

    .. note:: 2D: This calculation is defined for 2D systems only. However particle positions are still required to be \
    (x, y, 0)

    :param rmax: +/- r distance to search for neighbors
    :param k: symmetry of order parameter (:math:`k=6` is hexatic)
    :param n: number of neighbors (:math:`n=k` if :math:`n` not specified)
    :type rmax: float
    :type k: float
    :type n: unsigned int

    .. note:: While :math:`k` is a float, this is due to its use in calculations requiring floats. Passing in \
    non-integer values will result in undefined behavior
    """
    cdef order.HexOrderParameter *thisptr

    def __cinit__(self, rmax, k=float(6.0), n=int(0)):
        self.thisptr = new order.HexOrderParameter(rmax, k, n)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, box, points):
        """
        Calculates the correlation function and adds to the current histogram.

        :param box: simulation box
        :param points: points to calculate the order parameter
        :type box: :py:meth:`freud.trajectory.Box`
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        with nogil:
            self.thisptr.compute(l_box, <vec3[float]*>&l_points[0], nP)

    def getPsi(self):
        """
        :return: order parameter
        :rtype: np.complex64
        """
        cdef float complex *psi = self.thisptr.getPsi().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>psi)
        return result

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

    def getK(self):
        """
        Get the symmetry of the order parameter

        :return: k
        :rtype: float

        .. note:: While :math:`k` is a float, this is due to its use in calculations requiring floats. Passing in \
        non-integer values will result in undefined behavior
        """
        cdef float k = self.thisptr.getK()
        return k

cdef class LocalDescriptors:
    """Compute a set of descriptors (a numerical "fingerprint") of a particle's local environment.

    :param box: This Frame's box
    :param nNeigh: Number of neighbors to compute descriptors for
    :param lmax: Maximum spherical harmonic l to consider
    :param rmax: Initial guess of the maximum radius to looks for neighbors
    :type box: :py:meth:`freud.trajectory.Box()`
    :type nNeigh: unsigned int
    :type l: unsigned int
    :type rmax: float

    .. todo:: update constructor/compute to take box in compute

    """
    cdef order.LocalDescriptors *thisptr

    def __cinit__(self, box, nNeigh, lmax, rmax):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.LocalDescriptors(l_box, nNeigh, lmax, rmax)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, points, orientations):
        """
        Calculates the local descriptors.

        :param points: points to calculate the order parameter
        :param orientations: orientations to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        :type orientations: np.ndarray(shape=(N, 4), dtype=np.float32)
        """
        if points.dtype != np.float32 or orientations.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2 or orientations.ndim !=2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        if orientations.shape[1] != 4:
            raise ValueError("the 2nd dimension must have 4 values: q0, q1, q2, q3")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef np.ndarray[float, ndim=1] l_orientations = np.ascontiguousarray(orientations.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        with nogil:
            self.thisptr.compute(<vec3[float]*>&l_points[0], <quat[float]*>&l_orientations[0], nP)

    def getMagR(self):
        """
        Get a reference to the last computed radius magnitude array

        :return: MagR
        :rtype: np.float32
        """
        cdef float *magr = self.thisptr.getMagR().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>magr)
        return result

    def getQij(self):
        """
        Get a reference to the last computed relative orientation array

        :return: Qij
        :rtype: np.float32

        """
        cdef quat[float] *qij = self.thisptr.getQij().get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        nbins[1] = 4
        cdef np.ndarray[float, ndim=2] result = np.PyArray_SimpleNewFromData(2, nbins, np.NPY_FLOAT32, <void*>qij)
        return result

    def getSph(self):
        """
        Get a reference to the last computed spherical harmonic array

        :return: order parameter
        :rtype: np.complex64
        """
        cdef float complex *sph = self.thisptr.getSph().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>sph)
        return result

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

    def getNNeigh(self):
        """
        Get the number of neighbors

        :return: n
        :rtype: unsigned int

        """
        cdef unsigned int n = self.thisptr.getNNeigh()
        return n

    def getLMax(self):
        """
        Get the maximum spherical harmonic l to calculate for

        :return: l
        :rtype: unsigned int

        """
        cdef unsigned int l = self.thisptr.getLMax()
        return l

    def getRMax(self):
        """
        Get the cutoff radius

        :return: r
        :rtype: float

        """
        cdef float r = self.thisptr.getRMax()
        return r

cdef class TransOrderParameter:
    """Compute the translational order parameter for each particle

    :param rmax: +/- r distance to search for neighbors
    :param k: symmetry of order parameter (:math:`k=6` is hexatic)
    :param n: number of neighbors (:math:`n=k` if :math:`n` not specified)
    :type rmax: float
    :type k: float
    :type n: unsigned int

    """
    cdef order.TransOrderParameter *thisptr

    def __cinit__(self, rmax, k=6.0, n=0):
        self.thisptr = new order.TransOrderParameter(rmax, k, n)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, box, points, orientations):
        """
        Calculates the local descriptors.

        :param box: simulation box
        :param points: points to calculate the order parameter
        :type box: :py:meth:`freud.trajectory.Box`
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        with nogil:
            self.thisptr.compute(l_box, <vec3[float]*>&l_points[0], nP)

    def getDr(self):
        """
        Get a reference to the last computed spherical harmonic array

        :return: order parameter
        :rtype: np.complex64
        """
        cdef float complex *dr = self.thisptr.getDr().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>dr)
        return result

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class LocalQl:
    """Compute the local Steinhardt rotationally invariant Ql order parameter for a set of points.

    Implements the local rotationally invariant Ql order parameter described by Steinhardt. For a particle i, \
    we calculate the average :math:`Q_l` by summing the spherical harmonics between particle :math:`i` and its \
    neighbors :math:`j` in a local region: \
    :math:`\\overline{Q}_{lm}(i) = \\frac{1}{N_b} \\displaystyle\\sum_{j=1}^{N_b} Y_{lm}(\\theta(\\vec{r}_{ij}),\
    \\phi(\\vec{r}_{ij}))`

    This is then combined in a rotationally invariant fashion to remove local orientational order as follows:
    :math:`Q_l(i)=\\sqrt{\\frac{4\pi}{2l+1} \\displaystyle\\sum_{m=-l}^{l} |\\overline{Q}_{lm}|^2 }`

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average Ql order parameter for a set of points:

    * Variation of the Steinhardt Ql order parameter
    * For a particle i, we calculate the average Q_l by summing the spherical harmonics between particle i and its \
    neighbors j and the neighbors k of neighbor j in a local region
    * For more details see Wolfgan Lechner (2008) (DOI: 10.1063/Journal of Chemical Physics 129.114707)

    :param box: simulation box
    :param rmax: Cutoff radius for the local order parameter. Values near first minima of the rdf are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :param rmin: can look at only the second shell or some arbitrary rdf region
    :type box: :py:meth:`freud.trajectory.Box`
    :type rmax: float
    :type l: unsigned int
    :type rmin: float

    .. todo:: move box to compute, this is old API
    """
    cdef order.LocalQl *thisptr

    def __cinit__(self, box, rmax, l, rmin=0):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.LocalQl(l_box, rmax, l, rmin)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)

    def computeAve(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)

    def computeNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeNorm(<vec3[float]*>&l_points[0], nP)

    def computeAveNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAveNorm(<vec3[float]*>&l_points[0], nP)

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def setBox(self, box):
        """
        Reset the simulation box

        :param box: simulation box
        :type box: :py:meth:`freud.trajectory.Box`
        """
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    def getQl(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getAveQl(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getAveQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getQlNorm(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQlNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getQlAveNorm(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQlAveNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class LocalQlNear:
    """Compute the local Steinhardt rotationally invariant Ql order parameter for a set of points.

    Implements the local rotationally invariant Ql order parameter described by Steinhardt. For a particle i, \
    we calculate the average :math:`Q_l` by summing the spherical harmonics between particle :math:`i` and its \
    neighbors :math:`j` in a local region: \
    :math:`\\overline{Q}_{lm}(i) = \\frac{1}{N_b} \\displaystyle\\sum_{j=1}^{N_b} Y_{lm}(\\theta(\\vec{r}_{ij}),\
    \\phi(\\vec{r}_{ij}))`

    This is then combined in a rotationally invariant fashion to remove local orientational order as follows:
    :math:`Q_l(i)=\\sqrt{\\frac{4\pi}{2l+1} \\displaystyle\\sum_{m=-l}^{l} |\\overline{Q}_{lm}|^2 }`

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average Ql order parameter for a set of points:

    * Variation of the Steinhardt Ql order parameter
    * For a particle i, we calculate the average Q_l by summing the spherical harmonics between particle i and its \
    neighbors j and the neighbors k of neighbor j in a local region
    * For more details see Wolfgan Lechner (2008) (DOI: 10.1063/Journal of Chemical Physics 129.114707)

    :param box: simulation box
    :param rmax: Cutoff radius for the local order parameter. Values near first minima of the rdf are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :param kn: number of nearest neighbors. must be a positive integer
    :type box: :py:meth:`freud.trajectory.Box`
    :type rmax: float
    :type l: unsigned int
    :type kn: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.LocalQlNear *thisptr

    def __cinit__(self, box, rmax, l, kn=12):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.LocalQlNear(l_box, rmax, l, kn)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)

    def computeAve(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)

    def computeNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeNorm(<vec3[float]*>&l_points[0], nP)

    def computeAveNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAveNorm(<vec3[float]*>&l_points[0], nP)

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def setBox(self, box):
        """
        Reset the simulation box

        :param box: simulation box
        :type box: :py:meth:`freud.trajectory.Box`
        """
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    def getQl(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getAveQl(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getAveQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getQlNorm(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQlNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getQlAveNorm(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQlAveNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class LocalWl:
    """Compute the local Steinhardt rotationally invariant :math:`W_l` order parameter for a set of points.

    Implements the local rotationally invariant :math:`W_l` order parameter described by Steinhardt that can aid in distinguishing \
    between FCC, HCP, and BCC.

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average :math:`W_l` order parameter for a set of points:

    * Variation of the Steinhardt :math:`W_l` order parameter
    * For a particle i, we calculate the average :math:`W_l` by summing the spherical harmonics between particle i and its \
    neighbors j and the neighbors k of neighbor j in a local region
    * For more details see Wolfgan Lechner (2008) (DOI: 10.1063/Journal of Chemical Physics 129.114707)

    :param box: simulation box
    :param rmax: Cutoff radius for the local order parameter. Values near first minima of the rdf are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :type box: :py:meth:`freud.trajectory.Box`
    :type rmax: float
    :type l: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.LocalWl *thisptr

    def __cinit__(self, box, rmax, l):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.LocalWl(l_box, rmax, l)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)

    def computeAve(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)

    def computeNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeNorm(<vec3[float]*>&l_points[0], nP)

    def computeAveNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAveNorm(<vec3[float]*>&l_points[0], nP)

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def setBox(self, box):
        """
        Reset the simulation box

        :param box: simulation box
        :type box: :py:meth:`freud.trajectory.Box`
        """
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    def getQl(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getWl(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.complex64
        """
        cdef float complex *Wl = self.thisptr.getWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getAveWl(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Wl for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float complex *Wl = self.thisptr.getAveWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getWlNorm(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Wl for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float complex *Wl = self.thisptr.getWlNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getWlAveNorm(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Wl for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float complex *Wl = self.thisptr.getAveNormWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class LocalWlNear:
    """Compute the local Steinhardt rotationally invariant :math:`W_l` order parameter for a set of points.

    Implements the local rotationally invariant :math:`W_l` order parameter described by Steinhardt that can aid in distinguishing \
    between FCC, HCP, and BCC.

    For more details see PJ Steinhardt (1983) (DOI: 10.1103/PhysRevB.28.784)

    Added first/second shell combined average :math:`W_l` order parameter for a set of points:

    * Variation of the Steinhardt :math:`W_l` order parameter
    * For a particle i, we calculate the average :math:`W_l` by summing the spherical harmonics between particle i and its \
    neighbors j and the neighbors k of neighbor j in a local region
    * For more details see Wolfgan Lechner (2008) (DOI: 10.1063/Journal of Chemical Physics 129.114707)

    :param box: simulation box
    :param rmax: Cutoff radius for the local order parameter. Values near first minima of the rdf are recommended
    :param l: Spherical harmonic quantum number l.  Must be a positive number
    :param kn: Number of nearest neighbors. Must be a positive number
    :type box: :py:meth:`freud.trajectory.Box`
    :type rmax: float
    :type l: unsigned int
    :type kn: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.LocalWlNear *thisptr

    def __cinit__(self, box, rmax, l, kn=12):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.LocalWlNear(l_box, rmax, l, kn)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)

    def computeAve(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)

    def computeNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeNorm(<vec3[float]*>&l_points[0], nP)

    def computeAveNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAve(<vec3[float]*>&l_points[0], nP)
        self.thisptr.computeAveNorm(<vec3[float]*>&l_points[0], nP)

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def setBox(self, box):
        """
        Reset the simulation box

        :param box: simulation box
        :type box: :py:meth:`freud.trajectory.Box`
        """
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    def getQl(self):
        """
        Get a reference to the last computed Ql for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float *Ql = self.thisptr.getQl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[float, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*>Ql)
        return result

    def getWl(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Ql for particles with no neighbors.

        :return: order parameter
        :rtype: np.complex64
        """
        cdef float complex *Wl = self.thisptr.getWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getWlNorm(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Wl for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float complex *Wl = self.thisptr.getWlNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getAveWl(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Wl for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float complex *Wl = self.thisptr.getAveWl().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getWlAveNorm(self):
        """
        Get a reference to the last computed Wl for each particle.  Returns NaN instead of Wl for particles with no neighbors.

        :return: order parameter
        :rtype: np.float32
        """
        cdef float complex *Wl = self.thisptr.getWlAveNorm().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Wl)
        return result

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class SolLiq:
    """Computes dot products of qlm between particles and uses these for clustering.

    :param box: simulation box
    :param rmax: Cutoff radius for the local order parameter. Values near first minima of the rdf are recommended
    :param Qthreshold: Value of dot product threshold when evaluating :math:`Q_{lm}^*(i) Q_{lm}(j)` to determine \
    if a neighbor pair is a solid-like bond. (For :math:`l=6`, 0.7 generally good for FCC or BCC structures)
    :param Sthreshold: Minimum required number of adjacent solid-link bonds for a particle to be considered solid-like \
    for clustering. (For :math:`l=6`, 6-8 generally good for FCC or BCC structures)
    :param l: Choose spherical harmonic :math:`Q_l`.  Must be positive and even.
    :type box: :py:meth:`freud.trajectory.Box`
    :type rmax: float
    :type Qthreshold: float
    :type Sthreshold: unsigned int
    :type l: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.SolLiq *thisptr

    def __cinit__(self, box, rmax, Qthreshold, Sthreshold, l):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.SolLiq(l_box, rmax, Qthreshold, Sthreshold, l)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)

    def computeSolLiqVariant(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.computeSolLiqVariant(<vec3[float]*>&l_points[0], nP)

    def computeSolLiqNoNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.computeSolLiqNoNorm(<vec3[float]*>&l_points[0], nP)

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def setClusteringRadius(self, rcutCluster):
        """
        Reset the clustering radius

        :param rcutCluster: radius for the cluster finding
        :type rcutCluster: float
        """
        self.thisptr.setClusteringRadius(rcutCluster)

    def setBox(self, box):
        """
        Reset the simulation box

        :param box: simulation box
        :type box: :py:meth:`freud.trajectory.Box`
        """
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    def getLargestClusterSize(self):
        """
        Returns the largest cluster size. Must compute sol-liq first

        :return: largest cluster size
        :rtype: unsigned int
        """
        cdef unsigned int clusterSize = self.thisptr.getLargestClusterSize()
        return clusterSize

    def getClusterSizes(self):
        """
        Returns the largest cluster size. Must compute sol-liq first

        :return: largest cluster size
        :rtype: np.uint32

        .. todo:: unsure of the best way to pass back...as this doesn't do what I want
        """
        cdef vector[unsigned int] clusterSizes = self.thisptr.getClusterSizes()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNumClusters()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*>&clusterSizes)
        return result

    def getQlmi(self):
        """
        Get a reference to the last computed Qlmi for each particle.

        :return: order parameter
        :rtype: np.complex64
        """
        cdef float complex *Qlmi = self.thisptr.getQlmi().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Qlmi)
        return result

    def getClusters(self):
        """
        Get a reference to the last computed set of solid-like cluster indices for each particle

        :return: clusters
        :rtype: np.uint32
        """
        cdef unsigned int *clusters = self.thisptr.getClusters().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*>clusters)
        return result

    def getNumberOfConnections(self):
        """
        Get a reference to the number of connections per particle

        :return: clusters
        :rtype: np.uint32
        """
        cdef unsigned int *connections = self.thisptr.getNumberOfConnections().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*>connections)
        return result

    def getQldot_ij(self):
        """
        Get a reference to the qldot_ij values

        :return: largest cluster size
        :rtype: np.uint32

        .. todo:: figure out the size of this cause apparently its size is just its size
        """
        cdef vector[float complex] Qldot = self.thisptr.getQldot_ij()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNumClusters()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>&Qldot)
        return result

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class MatchEnv:
    """Clusters particles according to whether their local environments match or not, according to various shape matching metrics.

    :param box: Simulation box
    :param rmax: Cutoff radius for cell list and clustering algorithm. Values near first minima of the rdf are recommended.
    :param k: Number of nearest neighbors taken to define the local environment of any given particle.
    """
    cdef order.MatchEnv *thisptr

    def __cinit__(self, box, rmax, k):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.MatchEnv(l_box, rmax, k)

    def __dealloc__(self):
        del self.thisptr

    def setBox(self, box):
        """
        Reset the simulation box

        :param box: simulation box
        :type box: :py:meth:`freud.trajectory.Box`
        """
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    def cluster(self, points, threshold, hard_r=False, registration=False, global_search=False):
        """Determine clusters of particles with matching environments.

        :param points: particle positions
        :param threshold: maximum magnitude of the vector difference between two vectors, below which you call them matching
        :param hard_r: if true, add all particles that fall within the threshold of m_rmaxsq to the environment
        :param registration: if true, first use brute force registration to orient one set of environment vectors with respect to the other set such that it minimizes the RMSD between the two sets
        :param global_search: if true, do an exhaustive search wherein you compare the environments of every single pair of particles in the simulation. If false, only compare the environments of neighboring particles.
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        :type threshold: np.float32
        :type hard_r: bool
        :type registration: bool
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension of points must have 3 values: x, y, z")

        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]

        self.thisptr.cluster(<vec3[float]*>&l_points[0], nP, threshold, hard_r, registration, global_search)

    def matchMotif(self, points, refPoints, threshold, registration=False):
        """Determine clusters of particles that match the motif provided by refPoints.

        :param points: particle positions
        :param refPoints: vectors that make up the motif against which we are matching
        :param threshold: maximum magnitude of the vector difference between two vectors, below which you call them matching
        :param registration: if true, first use brute force registration to orient one set of environment vectors with respect to the other set such that it minimizes the RMSD between the two sets
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        :type refPoints: np.ndarray(shape=(num_neigh, 3), dtype=np.float32)
        :type threshold: np.float32
        :type hard_r: bool
        :type registration: bool
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension of points must have 3 values: x, y, z")
        if refPoints.dtype != np.float32:
            raise ValueError("refPoints must be a numpy float32 array")
        if refPoints.ndim != 2:
            raise ValueError("refPoints must be a 2 dimensional array")
        if refPoints.shape[1] != 3:
            raise ValueError("the 2nd dimension of refPoints must have 3 values: x, y, z")

        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef np.ndarray[float, ndim=1] l_refPoints = np.ascontiguousarray(refPoints.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef unsigned int nRef = <unsigned int> refPoints.shape[0]

        self.thisptr.matchMotif(<vec3[float]*>&l_points[0], nP, <vec3[float]*>&l_refPoints[0], nRef, threshold, registration)

    def isSimilar(self, refPoints1, refPoints2, threshold, registration=False):
        """Test if the motif provided by refPoints1 is similar to the motif provided by refPoints2.

        :param refPoints1: vectors that make up motif 1
        :param refPoints2: vectors that make up motif 2
        :param threshold: maximum magnitude of the vector difference between two vectors, below which you call them matching
        :param registration: if true, first use brute force registration to orient one set of environment vectors with respect to the other set such that it minimizes the RMSD between the two sets
        :type refPoints1: np.ndarray(shape=(num_neigh, 3), dtype=np.float32)
        :type refPoints2: np.ndarray(shape=(num_neigh, 3), dtype=np.float32)
        :type threshold: np.float32
        :type registration: bool
        :return: the mapping between the vectors of the environments that will make them correspond to each other. empty if they do not correspond to each other.
        :rtype: map[int, int]
        """
        if refPoints1.dtype != np.float32:
            raise ValueError("refPoints1 must be a numpy float32 array")
        if refPoints1.ndim != 2:
            raise ValueError("refPoints1 must be a 2 dimensional array")
        if refPoints1.shape[1] != 3:
            raise ValueError("the 2nd dimension of refPoints1 must have 3 values: x, y, z")
        if refPoints2.dtype != np.float32:
            raise ValueError("refPoints2 must be a numpy float32 array")
        if refPoints2.ndim != 2:
            raise ValueError("refPoints2 must be a 2 dimensional array")
        if refPoints2.shape[1] != 3:
            raise ValueError("the 2nd dimension of refPoints2 must have 3 values: x, y, z")

        cdef np.ndarray[float, ndim=1] l_refPoints1 = np.copy(np.ascontiguousarray(refPoints1.flatten()))
        cdef np.ndarray[float, ndim=1] l_refPoints2 = np.copy(np.ascontiguousarray(refPoints2.flatten()))
        cdef unsigned int nRef1 = <unsigned int> refPoints1.shape[0]
        cdef unsigned int nRef2 = <unsigned int> refPoints2.shape[0]
        cdef float threshold_sq = threshold*threshold

        if nRef1 != nRef2:
            raise ValueError("the number of vectors in refPoints1 must MATCH the number of vectors in refPoints2")

        cdef map[unsigned int, unsigned int] vec_map = self.thisptr.isSimilar(<vec3[float]*>&l_refPoints1[0], <vec3[float]*>&l_refPoints2[0], nRef1, threshold_sq, registration)
        cdef np.ndarray[float, ndim=2] rot_refPoints2 = np.reshape(l_refPoints2, (nRef2, 3))
        return [rot_refPoints2, vec_map]

    def minimizeRMSD(self, refPoints1, refPoints2, registration=False):
        """Get the somewhat-optimal RMSD between the set of vectors refPoints1 and the set of vectors refPoints2.

        :param refPoints1: vectors that make up motif 1
        :param refPoints2: vectors that make up motif 2
        :param registration: if true, first use brute force registration to orient one set of environment vectors with respect to the other set such that it minimizes the RMSD between the two sets
        :type refPoints1: np.ndarray(shape=(num_neigh, 3), dtype=np.float32)
        :type refPoints2: np.ndarray(shape=(num_neigh, 3), dtype=np.float32)
        :type registration: bool
        :return: a triplet that gives the associated min_rmsd, rotated (or not) set of refPoints2, and the mapping between the vectors of refPoints1 and refPoints2 that somewhat minimizes the RMSD.
        :rtype: tuple[float, np.ndarray(shape=(num_neigh, 3), dtype=np.float32), map[int, int]]
        """
        if refPoints1.dtype != np.float32:
            raise ValueError("refPoints1 must be a numpy float32 array")
        if refPoints1.ndim != 2:
            raise ValueError("refPoints1 must be a 2 dimensional array")
        if refPoints1.shape[1] != 3:
            raise ValueError("the 2nd dimension of refPoints1 must have 3 values: x, y, z")
        if refPoints2.dtype != np.float32:
            raise ValueError("refPoints2 must be a numpy float32 array")
        if refPoints2.ndim != 2:
            raise ValueError("refPoints2 must be a 2 dimensional array")
        if refPoints2.shape[1] != 3:
            raise ValueError("the 2nd dimension of refPoints2 must have 3 values: x, y, z")

        cdef np.ndarray[float, ndim=1] l_refPoints1 = np.copy(np.ascontiguousarray(refPoints1.flatten()))
        cdef np.ndarray[float, ndim=1] l_refPoints2 = np.copy(np.ascontiguousarray(refPoints2.flatten()))
        cdef unsigned int nRef1 = <unsigned int> refPoints1.shape[0]
        cdef unsigned int nRef2 = <unsigned int> refPoints2.shape[0]

        if nRef1 != nRef2:
            raise ValueError("the number of vectors in refPoints1 must MATCH the number of vectors in refPoints2")

        cdef float min_rmsd = -1
        cdef map[unsigned int, unsigned int] results_map = self.thisptr.minimizeRMSD(<vec3[float]*>&l_refPoints1[0], <vec3[float]*>&l_refPoints2[0], nRef1, min_rmsd, registration)
        cdef np.ndarray[float, ndim=2] rot_refPoints2 = np.reshape(l_refPoints2, (nRef2, 3))
        return [min_rmsd, rot_refPoints2, results_map]

    def getClusters(self):
        """
        Get a reference to the particles, indexed into clusters according to their matching local environments

        :return: clusters
        :rtype: np.uint32
        """
        cdef unsigned int *clusters = self.thisptr.getClusters().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*>clusters)
        return result

    def getEnvironment(self, i):
        """
        Returns the set of vectors defining the environment indexed by i

        :param i: environment index
        :type i: unsigned int
        :return: the array of vectors
        :rtype: list[list[float, float, float]]
        """
        cdef vec3[float] *environment = self.thisptr.getEnvironment(i).get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp>self.thisptr.getMaxNumNeighbors()
        nbins[1] = 3
        cdef np.ndarray[float, ndim=2] result = np.PyArray_SimpleNewFromData(2, nbins, np.NPY_FLOAT32, <void*>environment)
        return result

    def getTotEnvironment(self):
        """
        Returns the entire m_Np by m_maxk by 3 matrix of all environments for all particles

        :return: the array of vectors
        :rtype: list[list[list[float, float, float]]]
        """
        cdef vec3[float] *tot_environment = self.thisptr.getTotEnvironment().get()
        cdef np.npy_intp nbins[3]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        nbins[1] = <np.npy_intp>self.thisptr.getMaxNumNeighbors()
        nbins[2] = 3
        cdef np.ndarray[float, ndim=3] result = np.PyArray_SimpleNewFromData(3, nbins, np.NPY_FLOAT32, <void*>tot_environment)
        return result

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

    def getNumClusters(self):
        """
        Get the number of clusters

        :return: num_clust
        :rtype: unsigned int
        """
        cdef unsigned int num_clust = self.thisptr.getNumClusters()
        return num_clust

cdef class SolLiqNear:
    """Computes dot products of qlm between particles and uses these for clustering.

    :param box: simulation box
    :param rmax: Cutoff radius for the local order parameter. Values near first minima of the rdf are recommended
    :param Qthreshold: Value of dot product threshold when evaluating :math:`Q_{lm}^*(i) Q_{lm}(j)` to determine \
    if a neighbor pair is a solid-like bond. (For :math:`l=6`, 0.7 generally good for FCC or BCC structures)
    :param Sthreshold: Minimum required number of adjacent solid-link bonds for a particle to be considered solid-like \
    for clustering. (For :math:`l=6`, 6-8 generally good for FCC or BCC structures)
    :param l: Choose spherical harmonic :math:`Q_l`.  Must be positive and even.
    :param kn: Number of nearest neighbors. Must be a positive number
    :type box: :py:meth:`freud.trajectory.Box`
    :type rmax: float
    :type Qthreshold: float
    :type Sthreshold: unsigned int
    :type l: unsigned int
    :type kn: unsigned int

    .. todo:: move box to compute, this is old API
    """
    cdef order.SolLiqNear *thisptr

    def __cinit__(self, box, rmax, Qthreshold, Sthreshold, l, kn=12):
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr = new order.SolLiqNear(l_box, rmax, Qthreshold, Sthreshold, l, kn)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.compute(<vec3[float]*>&l_points[0], nP)

    def computeSolLiqVariant(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.computeSolLiqVariant(<vec3[float]*>&l_points[0], nP)

    def computeSolLiqNoNorm(self, points):
        """Compute the local rotationally invariant Ql order parameter.

        :param points: points to calculate the order parameter
        :type points: np.ndarray(shape=(N, 3), dtype=np.float32)
        """
        if points.dtype != np.float32:
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        self.thisptr.computeSolLiqNoNorm(<vec3[float]*>&l_points[0], nP)

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())

    def setClusteringRadius(self, rcutCluster):
        """
        Reset the clustering radius

        :param rcutCluster: radius for the cluster finding
        :type rcutCluster: float
        """
        self.thisptr.setClusteringRadius(rcutCluster)

    def setBox(self, box):
        """
        Reset the simulation box

        :param box: simulation box
        :type box: :py:meth:`freud.trajectory.Box`
        """
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.setBox(l_box)

    def getLargestClusterSize(self):
        """
        Returns the largest cluster size. Must compute sol-liq first

        :return: largest cluster size
        :rtype: unsigned int
        """
        cdef unsigned int clusterSize = self.thisptr.getLargestClusterSize()
        return clusterSize

    def getClusterSizes(self):
        """
        Returns the largest cluster size. Must compute sol-liq first

        :return: largest cluster size
        :rtype: np.uint32

        .. todo:: unsure of the best way to pass back...as this doesn't do what I want
        """
        cdef vector[unsigned int] clusterSizes = self.thisptr.getClusterSizes()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNumClusters()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*>&clusterSizes)
        return result

    def getQlmi(self):
        """
        Get a reference to the last computed Qlmi for each particle.

        :return: order parameter
        :rtype: np.complex64
        """
        cdef float complex *Qlmi = self.thisptr.getQlmi().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>Qlmi)
        return result

    def getClusters(self):
        """
        Get a reference to the last computed set of solid-like cluster indices for each particle

        :return: clusters
        :rtype: np.uint32
        """
        cdef unsigned int *clusters = self.thisptr.getClusters().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*>clusters)
        return result

    def getNumberOfConnections(self):
        """
        Get a reference to the number of connections per particle

        :return: clusters
        :rtype: np.uint32
        """
        cdef unsigned int *connections = self.thisptr.getNumberOfConnections().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp>self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*>connections)
        return result

    def getQldot_ij(self):
        """
        Get a reference to the qldot_ij values

        :return: largest cluster size
        :rtype: np.uint32

        .. todo:: figure out the size of this cause apparently its size is just its size
        """
        cdef vector[float complex] Qldot = self.thisptr.getQldot_ij()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNumClusters()
        cdef np.ndarray[np.complex64_t, ndim=1] result = np.PyArray_SimpleNewFromData(1, nbins, np.NPY_COMPLEX64, <void*>&Qldot)
        return result

    def getNP(self):
        """
        Get the number of particles

        :return: np
        :rtype: unsigned int
        """
        cdef unsigned int np = self.thisptr.getNP()
        return np

cdef class Pairing2D:
    """Compute pairs for the system of particles.

    :param rmax: distance over which to calculate
    :param k: number of neighbors to search
    :param compDotTol: value of the dot product below which a pair is determined
    :type rmax: float
    :type k: unsigned int
    :type compDotTol: float
    """
    cdef order.Pairing2D *thisptr

    def __cinit__(self, rmax, k, compDotTol):
        self.thisptr = new order.Pairing2D(rmax, k, compDotTol)

    def __dealloc__(self):
        del self.thisptr

    def compute(self, box, points, orientations, compOrientations):
        """
        Calculates the correlation function and adds to the current histogram.

        :param box: simulation box
        :param points: reference points to calculate the local density
        :param orientations: orientations to use in computation
        :param compOrientations: possible orientations to check for bonds
        :type box: :py:meth:`freud.trajectory.Box`
        :type points: np.float32
        :type orientations: np.float32
        :type compOrientations: np.float32
        """
        if (points.dtype != np.float32):
            raise ValueError("points must be a numpy float32 array")
        if points.ndim != 2:
            raise ValueError("points must be a 2 dimensional array")
        if points.shape[1] != 3:
            raise ValueError("the 2nd dimension must have 3 values: x, y, z")
        if (orientations.dtype != np.float32) or (compOrientations.dtype != np.float32):
            raise ValueError("values must be a numpy float32 array")
        if orientations.ndim != 1:
            raise ValueError("values must be a 1 dimensional array")
        if compOrientations.ndim != 2:
            raise ValueError("values must be a 2 dimensional array")
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(points.flatten())
        cdef np.ndarray[float, ndim=1] l_compOrientations = np.ascontiguousarray(compOrientations.flatten())
        cdef np.ndarray[float, ndim=1] l_orientations = np.ascontiguousarray(orientations.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef unsigned int nO = <unsigned int> compOrientations.shape[1]
        cdef _trajectory.Box l_box = _trajectory.Box(box.getLx(), box.getLy(), box.getLz(), box.getTiltFactorXY(), box.getTiltFactorXZ(), box.getTiltFactorYZ(), box.is2D())
        self.thisptr.compute(l_box, <vec3[float]*>&l_points[0], <float*>&l_orientations[0], <float*>&l_compOrientations[0], nP, nO)

    def getMatch(self):
        """
        :return: match
        :rtype: np.uint32
        """
        cdef unsigned int *match = self.thisptr.getMatch().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNumParticles()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(2, nbins, np.NPY_UINT32, <void*>match)
        return result

    def getPair(self):
        """
        :return: pair
        :rtype: np.uint32
        """
        cdef unsigned int *pair = self.thisptr.getPair().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp>self.thisptr.getNumParticles()
        cdef np.ndarray[np.uint32_t, ndim=1] result = np.PyArray_SimpleNewFromData(2, nbins, np.NPY_UINT32, <void*>pair)
        return result

    def getBox(self):
        """
        Get the box used in the calculation

        :return: Freud Box
        :rtype: :py:meth:`freud.trajectory.Box()`
        """
        return BoxFromCPP(<trajectory.Box> self.thisptr.getBox())
