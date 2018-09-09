# Copyright (c) 2010-2018 The Regents of the University of Michigan
# This file is from the freud project, released under the BSD 3-Clause License.

R"""
The environment module contains functions which characterize the local
environments of particles in the system. These methods use the positions and
orientations of particles in the local neighborhood of a given particle to
characterize the particle environment.
"""

import freud.common
import numpy as np
import warnings
from freud.errors import FreudDeprecationWarning
import freud.locality

from freud.util._VectorMath cimport vec3, quat
from libcpp.complex cimport complex
from libcpp.vector cimport vector
from libcpp.map cimport map
from libcpp.pair cimport pair
from libcpp.memory cimport shared_ptr
from cython.operator cimport dereference
cimport freud.box
cimport freud._environment
cimport freud.locality

cimport numpy as np

# numpy must be initialized. When using numpy from C or Cython you must
# _always_ do that, or you will have segfaults
np.import_array()


cdef class BondOrder:
    """Compute the bond orientational order diagram for the system of
    particles.

    The bond orientational order diagram (BOOD) is a way of studying the
    average local environments experienced by particles. In a BOOD, a particle
    and its nearest neighbors (determined by either a prespecified number of
    neighbors or simply a cutoff distance) are treated as connected by a bond
    joining their centers. All of the bonds in the system are then binned by
    their azimuthal (:math:`\\theta`) and polar (:math:`\\phi`) angles to
    indicate the location of a particle's neighbors relative to itself. The
    distance between the particle and its neighbor is only important when
    determining whether it is counted as a neighbor, but is not part of the
    BOOD; as such, the BOOD can be viewed as a projection of all bonds onto the
    unit sphere. The resulting 2D histogram provides insight into how particles
    are situated relative to one-another in a system.

    This class provides access to the classical BOOD as well as a few useful
    variants. These variants can be accessed *via* the :code:`mode` arguments
    to the :py:meth:`~BondOrder.compute` or :py:meth:`~BondOrder.accumulate`
    methods. Available modes of calculation are:

    * :code:`'bod'` (Bond Order Diagram, *default*):
      This mode constructs the default BOOD, which is the 2D histogram
      containing the number of bonds formed through each azimuthal
      :math:`\\left( \\theta \\right)` and polar :math:`\\left( \\phi \\right)`
      angle.

    * :code:`'lbod'` (Local Bond Order Diagram):
      In this mode, a particle's neighbors are rotated into the local frame of
      the particle before the BOOD is calculated, *i.e.* the directions of
      bonds are determined relative to the orientation of the particle rather
      than relative to the global reference frame. An example of when this mode
      would be useful is when a system is composed of multiple grains of the
      same crystal; the normal BOOD would show twice as many peaks as expected,
      but using this mode, the bonds would be superimposed.

    * :code:`'obcd'` (Orientation Bond Correlation Diagram):
      This mode aims to quantify the degree of orientational as well as
      translational ordering. As a first step, the rotation that would align a
      particle's neighbor with the particle is calculated. Then, the neighbor
      is rotated **around the central particle** by that amount, which actually
      changes the direction of the bond. One example of how this mode could be
      useful is in identifying plastic crystals, which exhibit translational
      but not orientational ordering. Normally, the BOOD for a plastic crystal
      would exhibit clear structure since there is translational order, but
      with this mode, the neighbor positions would actually be modified,
      resulting in an isotropic (disordered) BOOD.

    * :code:`'oocd'` (Orientation Orientation Correlation Diagram):
      This mode is substantially different from the other modes. Rather than
      compute the histogram of neighbor bonds, this mode instead computes a
      histogram of the directors of neighboring particles, where the director
      is defined as the basis vector :math:`\\hat{z}` rotated by the neighbor's
      quaternion. The directors are then rotated into the central particle's
      reference frame. This mode provides insight into the local orientational
      environment of particles, indicating, on average, how a particle's
      neighbors are oriented.

    .. moduleauthor:: Erin Teich <erteich@umich.edu>

    Args:
        r_max (float):
            Distance over which to calculate.
        k (unsigned int):
            Order parameter i. To be removed.
        n (unsigned int):
            Number of neighbors to find.
        n_bins_t (unsigned int):
            Number of :math:`\\theta` bins.
        n_bins_p (unsigned int):
            Number of :math:`\\phi` bins.

    Attributes:
        bond_order (:math:`\\left(N_{\\phi}, N_{\\theta} \\right)` :class:`numpy.ndarray`):
            Bond order.
        box (:py:class:`freud.box.Box`):
            Box used in the calculation.
        theta (:math:`\\left(N_{\\theta} \\right)` :class:`numpy.ndarray`):
            The values of bin centers for :math:`\\theta`.
        phi (:math:`\\left(N_{\\phi} \\right)` :class:`numpy.ndarray`):
            The values of bin centers for :math:`\\phi`.
        n_bins_theta (unsigned int):
            The number of bins in the :math:`\\theta` dimension.
        n_bins_phi (unsigned int):
            The number of bins in the :math:`\\phi` dimension.

    .. todo:: remove k, it is not used as such.
    """  # noqa: E501
    def __cinit__(self, float rmax, float k, unsigned int n,
                  unsigned int n_bins_t, unsigned int n_bins_p):
        self.thisptr = new freud._environment.BondOrder(
            rmax, k, n, n_bins_t, n_bins_p)
        self.rmax = rmax
        self.num_neigh = n

    def __dealloc__(self):
        del self.thisptr

    def accumulate(self, box, ref_points, ref_orientations, points=None,
                   orientations=None, str mode="bod", nlist=None):
        """Calculates the correlation function and adds to the current
        histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            ref_points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate bonds.
            ref_orientations ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                Reference orientations used to calculate bonds.
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`,
            optional):
                Points used to calculate bonds. Uses :code:`ref_points` if not
                provided or :code:`None`.
            orientations ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Orientations used to calculate bonds. Uses
                :code:`ref_orientations` if not provided or :code:`None`.
            mode (str, optional):
                Mode to calculate bond order. Options are :code:`'bod'`,
                :code:`'lbod'`, :code:`'obcd'`, or :code:`'oocd'`
                (Default value = :code:`'bod'`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa: E501
        cdef freud.box.Box b = freud.common.convert_box(box)

        if points is None:
            points = ref_points
        if orientations is None:
            orientations = ref_orientations

        ref_points = freud.common.convert_array(
            ref_points, 2, dtype=np.float32, contiguous=True,
            array_name="ref_points")
        if ref_points.shape[1] != 3:
            raise TypeError('ref_points should be an Nx3 array')

        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True, array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        ref_orientations = freud.common.convert_array(
            ref_orientations, 2, dtype=np.float32, contiguous=True,
            array_name="ref_orientations")
        if ref_orientations.shape[1] != 4:
            raise TypeError('ref_orientations should be an Nx4 array')

        orientations = freud.common.convert_array(
            orientations, 2, dtype=np.float32, contiguous=True,
            array_name="orientations")
        if orientations.shape[1] != 4:
            raise TypeError('orientations should be an Nx4 array')

        cdef unsigned int index = 0
        if mode == "bod":
            index = 0
        elif mode == "lbod":
            index = 1
        elif mode == "obcd":
            index = 2
        elif mode == "oocd":
            index = 3
        else:
            raise RuntimeError(
                ('Unknown BOD mode: {}. Options are:'
                    'bod, lbod, obcd, oocd.').format(mode))

        defaulted_nlist = freud.locality.make_default_nlist_nn(
            b, ref_points, points, self.num_neigh, nlist, None, self.rmax)
        cdef freud.locality.NeighborList nlist_ = defaulted_nlist[0]

        cdef np.ndarray[float, ndim=2] l_ref_points = ref_points
        cdef np.ndarray[float, ndim=2] l_points = points
        cdef np.ndarray[float, ndim=2] l_ref_orientations = ref_orientations
        cdef np.ndarray[float, ndim=2] l_orientations = orientations
        cdef unsigned int n_ref = <unsigned int> ref_points.shape[0]
        cdef unsigned int n_p = <unsigned int> points.shape[0]

        with nogil:
            self.thisptr.accumulate(
                dereference(b.thisptr), nlist_.get_ptr(),
                <vec3[float]*> l_ref_points.data,
                <quat[float]*> l_ref_orientations.data,
                n_ref,
                <vec3[float]*> l_points.data,
                <quat[float]*> l_orientations.data,
                n_p,
                index)
        return self

    @property
    def bond_order(self):
        cdef float * bod = self.thisptr.getBondOrder().get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp> self.thisptr.getNBinsPhi()
        nbins[1] = <np.npy_intp> self.thisptr.getNBinsTheta()
        cdef np.ndarray[float, ndim=2] result = np.PyArray_SimpleNewFromData(
            2, nbins, np.NPY_FLOAT32, <void*> bod)

        # Because we divide by the surface areas, the bond order will actually
        # be nans if we try to get the bond_order after resetting. This fixes
        # that.
        if np.all(np.isnan(result)):
            result = np.zeros((nbins[0], nbins[1]), dtype=np.float32)
        return result

    def getBondOrder(self):
        warnings.warn("The getBondOrder function is deprecated in favor "
                      "of the bond_order class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.bond_order

    @property
    def box(self):
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    def getBox(self):
        warnings.warn("The getBox function is deprecated in favor "
                      "of the box class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.box

    def reset(self):
        """Resets the values of the bond order in memory."""
        self.thisptr.reset()

    def resetBondOrder(self):
        warnings.warn("Use .reset() instead of this method. "
                      "This method will be removed in the future.",
                      FreudDeprecationWarning)
        self.reset()

    def compute(self, box, ref_points, ref_orientations, points=None,
                orientations=None, mode="bod", nlist=None):
        """Calculates the bond order histogram. Will overwrite the current
        histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            ref_points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate bonds.
            ref_orientations ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                Reference orientations used to calculate bonds.
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`,
            optional):
                Points used to calculate bonds. Uses :code:`ref_points` if not
                provided or :code:`None`.
            orientations ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`,
            optional):
                Orientations used to calculate bonds. Uses
                :code:`ref_orientations` if not provided or :code:`None`.
            mode (str, optional):
                Mode to calculate bond order. Options are :code:`'bod'`,
                :code:`'lbod'`, :code:`'obcd'`, or :code:`'oocd'`
                (Default value = :code:`'bod'`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa: E501
        self.reset()
        self.accumulate(box, ref_points, ref_orientations,
                        points, orientations, mode, nlist)
        return self

    def reduceBondOrder(self):
        warnings.warn("This method is automatically called internally. It "
                      "will be removed in the future.",
                      FreudDeprecationWarning)
        self.thisptr.reduceBondOrder()

    @property
    def theta(self):
        cdef float * theta = self.thisptr.getTheta().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp> self.thisptr.getNBinsTheta()
        cdef np.ndarray[np.float32_t, ndim=1] result = \
            np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32,
                                         <void*> theta)
        return result

    def getTheta(self):
        warnings.warn("The getTheta function is deprecated in favor "
                      "of the theta class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.theta

    @property
    def phi(self):
        cdef float * phi = self.thisptr.getPhi().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp> self.thisptr.getNBinsPhi()
        cdef np.ndarray[np.float32_t, ndim=1] result = \
            np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32, <void*> phi)
        return result

    def getPhi(self):
        warnings.warn("The getPhi function is deprecated in favor "
                      "of the phi class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.phi

    @property
    def n_bins_theta(self):
        cdef unsigned int nt = self.thisptr.getNBinsTheta()
        return nt

    def getNBinsTheta(self):
        warnings.warn("The getNBinsTheta function is deprecated in favor "
                      "of the n_bins_theta class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.n_bins_theta

    @property
    def n_bins_phi(self):
        cdef unsigned int np = self.thisptr.getNBinsPhi()
        return np

    def getNBinsPhi(self):
        warnings.warn("The getNBinsPhi function is deprecated in favor "
                      "of the n_bins_phi class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.n_bins_phi


cdef class LocalDescriptors:
    """Compute a set of descriptors (a numerical "fingerprint") of a particle's
    local environment.

    The resulting spherical harmonic array will be a complex-valued
    array of shape `(num_bonds, num_sphs)`. Spherical harmonic
    calculation can be restricted to some number of nearest neighbors
    through the `num_neighbors` argument; if a particle has more bonds
    than this number, the last one or more rows of bond spherical
    harmonics for each particle will not be set.

    .. note: **You must always call computeNList before calling compute, the
             NeighborList will not be populated until this is called. However,
             the compute method must be called to actually calculate the
             descriptors.**

    .. moduleauthor:: Matthew Spellings <mspells@umich.edu>

    Args:
        num_neighbors (unsigned int):
            Maximum number of neighbors to compute descriptors for.
        lmax (unsigned int):
            Maximum spherical harmonic :math:`l` to consider.
        rmax (float):
            Initial guess of the maximum radius to looks for neighbors.
        negative_m (bool):
            True if we should also calculate :math:`Y_{lm}` for negative
            :math:`m`.

    Attributes:
        sph (:math:`\\left(N_{bonds}, \\text{SphWidth} \\right)` :class:`numpy.ndarray`):
            A reference to the last computed spherical harmonic array.
        num_particles (unsigned int):
            The number of points passed to the last call to :meth:`~.compute`.
        num_neighbors (unsigned int):
            The number of neighbors used by the last call to compute. Bounded
            from above by the number of reference points multiplied by the
            lower of the num_neighbors arguments passed to the last compute
            call or the constructor.
        l_max (unsigned int):
            The maximum spherical harmonic :math:`l` to calculate for.
        r_max (float):
            The cutoff radius.
    """  # noqa: E501
    known_modes = {'neighborhood': freud._environment.LocalNeighborhood,
                   'global': freud._environment.Global,
                   'particle_local': freud._environment.ParticleLocal}

    def __cinit__(self, num_neighbors, lmax, rmax, negative_m=True):
        self.thisptr = new freud._environment.LocalDescriptors(
            num_neighbors, lmax, rmax, negative_m)
        self.num_neigh = num_neighbors
        self.rmax = rmax

    def __dealloc__(self):
        del self.thisptr

    def computeNList(self, box, points_ref, points=None):
        """Compute the neighbor list for bonds from a set of source points to
        a set of destination points.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points_ref ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Source points to calculate the order parameter.
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`, optional):
                Destination points to calculate the order parameter
                (Default value = :code:`None`).
        """  # noqa: E501
        cdef freud.box.Box b = freud.common.convert_box(box)

        points_ref = freud.common.convert_array(
            points_ref, 2, dtype=np.float32, contiguous=True,
            array_name="points_ref")
        if points_ref.shape[1] != 3:
            raise TypeError('points_ref should be an Nx3 array')

        if points is None:
            points = points_ref

        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True, array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim=2] l_points_ref = points_ref
        cdef unsigned int nRef = <unsigned int> points_ref.shape[0]
        cdef np.ndarray[float, ndim=2] l_points = points
        cdef unsigned int nP = <unsigned int> points.shape[0]
        with nogil:
            self.thisptr.computeNList(
                dereference(b.thisptr), <vec3[float]*> l_points_ref.data,
                nRef, <vec3[float]*> l_points.data, nP)
        return self

    def compute(self, box, unsigned int num_neighbors, points_ref, points=None,
                orientations=None, mode='neighborhood', nlist=None):
        """Calculates the local descriptors of bonds from a set of source
        points to a set of destination points.

        .. note: **You must always call computeNList before this method.**

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            num_neighbors (unsigned int):
                Number of neighbors to compute with or to limit to, if the
                neighbor list is precomputed.
            points_ref ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Source points to calculate the order parameter.
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`, optional):
                Destination points to calculate the order parameter
                (Default value = :code:`None`).
            orientations ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`, optional):
                Orientation of each reference point (Default value =
                :code:`None`).
            mode (str, optional):
                Orientation mode to use for environments, either
                :code:`'neighborhood'` to use the orientation of the local
                neighborhood, :code:`'particle_local'` to use the given
                particle orientations, or :code:`'global'` to not rotate
                environments (Default value = :code:`'neighborhood'`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds or :code:`'precomputed'` if
                using :py:meth:`~.computeNList` (Default value = :code:`None`).
        """  # noqa: E501
        cdef freud.box.Box b = freud.common.convert_box(box)

        if mode not in self.known_modes:
            raise RuntimeError(
                'Unknown LocalDescriptors orientation mode: {}'.format(mode))

        points_ref = freud.common.convert_array(
            points_ref, 2, dtype=np.float32, contiguous=True,
            array_name="points_ref")
        if points_ref.shape[1] != 3:
            raise TypeError('points_ref should be an Nx3 array')

        if points is None:
            points = points_ref

        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True, array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        cdef np.ndarray[float, ndim=2] l_orientations = orientations
        if mode == 'particle_local':
            if orientations is None:
                raise RuntimeError(
                    ('Orientations must be given to orient LocalDescriptors '
                        'with particles\' orientations'))

            orientations = freud.common.convert_array(
                orientations, 2, dtype=np.float32, contiguous=True,
                array_name="orientations")
            if orientations.shape[1] != 4:
                raise TypeError('orientations should be an Nx4 array')

            if orientations.shape[0] != points_ref.shape[0]:
                raise ValueError(
                    "orientations must have the same size as points_ref")

            l_orientations = orientations

        cdef np.ndarray[float, ndim=2] l_points_ref = points_ref
        cdef unsigned int nRef = <unsigned int> points_ref.shape[0]
        cdef np.ndarray[float, ndim=2] l_points = points
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef freud._environment.LocalDescriptorOrientation l_mode

        l_mode = self.known_modes[mode]

        self.num_neigh = num_neighbors

        cdef freud.locality.NeighborList nlist_ = None
        if not nlist == 'precomputed':
            defaulted_nlist = freud.locality.make_default_nlist_nn(
                b, points_ref, points, self.num_neigh, nlist,
                True, self.rmax)
            nlist_ = defaulted_nlist[0]

        with nogil:
            self.thisptr.compute(
                dereference(b.thisptr),
                nlist_.get_ptr() if nlist_ is not None else NULL,
                num_neighbors,
                <vec3[float]*> l_points_ref.data,
                nRef, <vec3[float]*> l_points.data, nP,
                <quat[float]*> l_orientations.data, l_mode)
        return self

    @property
    def sph(self):
        cdef float complex * sph = self.thisptr.getSph().get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp> self.thisptr.getNSphs()
        nbins[1] = <np.npy_intp> self.thisptr.getSphWidth()
        cdef np.ndarray[np.complex64_t, ndim=2] result = \
            np.PyArray_SimpleNewFromData(2, nbins, np.NPY_COMPLEX64,
                                         <void*> sph)
        return result

    def getSph(self):
        warnings.warn("The getSph function is deprecated in favor "
                      "of the sph class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.sph

    @property
    def num_particles(self):
        cdef unsigned int np = self.thisptr.getNP()
        return np

    def getNP(self):
        warnings.warn("The getNP function is deprecated in favor "
                      "of the num_particles class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.num_particles

    @property
    def num_neighbors(self):
        cdef unsigned int n = self.thisptr.getNSphs()
        return n

    def getNSphs(self):
        warnings.warn("The getNSphs function is deprecated in favor "
                      "of the num_neighbors class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.num_neighbors

    @property
    def l_max(self):
        cdef unsigned int l_max = self.thisptr.getLMax()
        return l_max

    def getLMax(self):
        warnings.warn("The getLMax function is deprecated in favor "
                      "of the l_max class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.l_max


cdef class MatchEnv:
    """Clusters particles according to whether their local environments match
    or not, according to various shape matching metrics.

    .. moduleauthor:: Erin Teich <erteich@umich.edu>

    Args:
        box (:class:`freud.box.Box`):
            Simulation box.
        rmax (float):
            Cutoff radius for cell list and clustering algorithm. Values near
            the first minimum of the RDF are recommended.
        k (unsigned int):
            Number of nearest neighbors taken to define the local environment
            of any given particle.

    Attributes:
        tot_environment (:math:`\\left(N_{particles}, N_{neighbors}, 3\\right)` :class:`numpy.ndarray`):
            All environments for all particles.
        num_particles (unsigned int):
            The number of particles.
        num_clusters (unsigned int):
            The number of clusters.
        clusters (:math:`\\left(N_{particles}\\right)` :class:`numpy.ndarray`):
            The per-particle index indicating cluster membership.
    """  # noqa: E501
    def __cinit__(self, box, rmax, k):
        cdef freud.box.Box b = freud.common.convert_box(box)

        self.thisptr = new freud._environment.MatchEnv(
            dereference(b.thisptr), rmax, k)

        self.rmax = rmax
        self.num_neigh = k
        self.m_box = box

    def __dealloc__(self):
        del self.thisptr

    def setBox(self, box):
        """Reset the simulation box.

        Args:
            box (:class:`freud.box.Box`): Simulation box.
        """
        cdef freud.box.Box b = freud.common.convert_box(box)
        self.thisptr.setBox(dereference(b.thisptr))
        self.m_box = box

    def cluster(self, points, threshold, hard_r=False, registration=False,
                global_search=False, env_nlist=None, nlist=None):
        """Determine clusters of particles with matching environments.

        Args:
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Destination points to calculate the order parameter.
            threshold (float):
                Maximum magnitude of the vector difference between two vectors,
                below which they are "matching."
            hard_r (bool):
                If True, add all particles that fall within the threshold of
                m_rmaxsq to the environment.
            registration (bool):
                If True, first use brute force registration to orient one set
                of environment vectors with respect to the other set such that
                it minimizes the RMSD between the two sets.
            global_search (bool):
                If True, do an exhaustive search wherein the environments of
                every single pair of particles in the simulation are compared.
                If False, only compare the environments of neighboring
                particles.
            env_nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find the environment of every particle
                (Default value = :code:`None`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find neighbors of every particle, to
                compare environments (Default value = :code:`None`).
        """
        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True,
            array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        # keeping the below syntax seems to be crucial for passing unit tests
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(
            points.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]

        cdef freud.locality.NeighborList nlist_
        cdef freud.locality.NeighborList env_nlist_
        if hard_r:
            defaulted_nlist = freud.locality.make_default_nlist(
                self.m_box, points, points, self.rmax, nlist, True)
            nlist_ = defaulted_nlist[0]

            defaulted_env_nlist = freud.locality.make_default_nlist(
                self.m_box, points, points, self.rmax, env_nlist, True)
            env_nlist_ = defaulted_env_nlist[0]
        else:
            defaulted_nlist = freud.locality.make_default_nlist_nn(
                self.m_box, points, points, self.num_neigh, nlist,
                None, self.rmax)
            nlist_ = defaulted_nlist[0]

            defaulted_env_nlist = freud.locality.make_default_nlist_nn(
                self.m_box, points, points, self.num_neigh, env_nlist,
                None, self.rmax)
            env_nlist_ = defaulted_env_nlist[0]

        # keeping the below syntax seems to be crucial for passing unit tests
        self.thisptr.cluster(
            env_nlist_.get_ptr(), nlist_.get_ptr(),
            <vec3[float]*> &l_points[0], nP, threshold, hard_r, registration,
            global_search)

    def matchMotif(self, points, refPoints, threshold, registration=False,
                   nlist=None):
        """Determine clusters of particles that match the motif provided by
        refPoints.

        Args:
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Particle positions.
            refPoints ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Vectors that make up the motif against which we are matching.
            threshold (float):
                Maximum magnitude of the vector difference between two vectors,
                below which they are considered "matching."
            registration (bool, optional):
                If True, first use brute force registration to orient one set
                of environment vectors with respect to the other set such that
                it minimizes the RMSD between the two sets
                (Default value = False).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """
        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True,
            array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        refPoints = freud.common.convert_array(
            refPoints, 2, dtype=np.float32, contiguous=True,
            array_name="refPoints")
        if refPoints.shape[1] != 3:
            raise TypeError('refPoints should be an Nx3 array')

        # keeping the below syntax seems to be crucial for passing unit tests
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(
            points.flatten())
        cdef np.ndarray[float, ndim=1] l_refPoints = np.ascontiguousarray(
            refPoints.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef unsigned int nRef = <unsigned int> refPoints.shape[0]

        defaulted_nlist = freud.locality.make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, None, self.rmax)
        cdef freud.locality.NeighborList nlist_ = defaulted_nlist[0]

        # keeping the below syntax seems to be crucial for passing unit tests
        self.thisptr.matchMotif(
            nlist_.get_ptr(), <vec3[float]*> &l_points[0], nP,
            <vec3[float]*> &l_refPoints[0], nRef, threshold,
            registration)

    def minRMSDMotif(self, points, refPoints, registration=False, nlist=None):
        """Rotate (if registration=True) and permute the environments of all
        particles to minimize their RMSD with respect to the motif provided by
        refPoints.

        Args:
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Particle positions.
            refPoints ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Vectors that make up the motif against which we are matching.
            registration (bool, optional):
                If True, first use brute force registration to orient one set
                of environment vectors with respect to the other set such that
                it minimizes the RMSD between the two sets
                (Default value = False).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        Returns:
            :math:`\\left(N_{particles}\\right)` :class:`numpy.ndarray`:
                Vector of minimal RMSD values, one value per particle.

        """
        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True,
            array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        refPoints = freud.common.convert_array(
            refPoints, 2, dtype=np.float32, contiguous=True,
            array_name="refPoints")
        if refPoints.shape[1] != 3:
            raise TypeError('refPoints should be an Nx3 array')

        # keeping the below syntax seems to be crucial for passing unit tests
        cdef np.ndarray[float, ndim=1] l_points = np.ascontiguousarray(
            points.flatten())
        cdef np.ndarray[float, ndim=1] l_refPoints = np.ascontiguousarray(
            refPoints.flatten())
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef unsigned int nRef = <unsigned int> refPoints.shape[0]

        defaulted_nlist = freud.locality.make_default_nlist_nn(
            self.m_box, points, points, self.num_neigh, nlist, None, self.rmax)
        cdef freud.locality.NeighborList nlist_ = defaulted_nlist[0]

        # keeping the below syntax seems to be crucial for passing unit tests
        cdef vector[float] min_rmsd_vec = self.thisptr.minRMSDMotif(
            nlist_.get_ptr(), <vec3[float]*> &l_points[0], nP,
            <vec3[float]*> &l_refPoints[0], nRef, registration)

        return min_rmsd_vec

    def isSimilar(self, refPoints1, refPoints2, threshold, registration=False):
        """Test if the motif provided by refPoints1 is similar to the motif
        provided by refPoints2.

        Args:
            refPoints1 ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Vectors that make up motif 1.
            refPoints2 ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Vectors that make up motif 2.
            threshold (float):
                Maximum magnitude of the vector difference between two vectors,
                below which they are considered "matching."
            registration (bool, optional):
                If True, first use brute force registration to orient one set
                of environment vectors with respect to the other set such that
                it minimizes the RMSD between the two sets
                (Default value = False).

        Returns:
            tuple ((:math:`\\left(N_{particles}, 3\\right)` :class:`numpy.ndarray`), map[int, int]):
                A doublet that gives the rotated (or not) set of
                :code:`refPoints2`, and the mapping between the vectors of
                :code:`refPoints1` and :code:`refPoints2` that will make them
                correspond to each other. Empty if they do not correspond to
                each other.
        """  # noqa: E501
        refPoints1 = freud.common.convert_array(
            refPoints1, 2, dtype=np.float32, contiguous=True,
            array_name="refPoints1")
        if refPoints1.shape[1] != 3:
            raise TypeError('refPoints1 should be an Nx3 array')

        refPoints2 = freud.common.convert_array(
            refPoints2, 2, dtype=np.float32, contiguous=True,
            array_name="refPoints2")
        if refPoints2.shape[1] != 3:
            raise TypeError('refPoints2 should be an Nx3 array')

        # keeping the below syntax seems to be crucial for passing unit tests
        cdef np.ndarray[float, ndim=1] l_refPoints1 = np.copy(
            np.ascontiguousarray(refPoints1.flatten()))
        cdef np.ndarray[float, ndim=1] l_refPoints2 = np.copy(
            np.ascontiguousarray(refPoints2.flatten()))
        cdef unsigned int nRef1 = <unsigned int> refPoints1.shape[0]
        cdef unsigned int nRef2 = <unsigned int> refPoints2.shape[0]
        cdef float threshold_sq = threshold*threshold

        if nRef1 != nRef2:
            raise ValueError(
                ("The number of vectors in refPoints1 must MATCH the number of"
                    "vectors in refPoints2"))

        # keeping the below syntax seems to be crucial for passing unit tests
        cdef map[unsigned int, unsigned int] vec_map = self.thisptr.isSimilar(
            <vec3[float]*> &l_refPoints1[0],
            <vec3[float]*> &l_refPoints2[0],
            nRef1, threshold_sq, registration)
        cdef np.ndarray[float, ndim=2] rot_refPoints2 = np.reshape(
            l_refPoints2, (nRef2, 3))
        return [rot_refPoints2, vec_map]

    def minimizeRMSD(self, refPoints1, refPoints2, registration=False):
        """Get the somewhat-optimal RMSD between the set of vectors refPoints1
        and the set of vectors refPoints2.

        Args:
            refPoints1 ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Vectors that make up motif 1.
            refPoints2 ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Vectors that make up motif 2.
            registration (bool, optional):
                If true, first use brute force registration to orient one set
                of environment vectors with respect to the other set such that
                it minimizes the RMSD between the two sets
                (Default value = False).

        Returns:
            tuple (float, (:math:`\\left(N_{particles}, 3\\right)` :class:`numpy.ndarray`), map[int, int]):
                A triplet that gives the associated min_rmsd, rotated (or not)
                set of refPoints2, and the mapping between the vectors of
                refPoints1 and refPoints2 that somewhat minimizes the RMSD.
        """  # noqa: E501
        refPoints1 = freud.common.convert_array(
            refPoints1, 2, dtype=np.float32, contiguous=True,
            array_name="refPoints1")
        if refPoints1.shape[1] != 3:
            raise TypeError('refPoints1 should be an Nx3 array')

        refPoints2 = freud.common.convert_array(
            refPoints2, 2, dtype=np.float32, contiguous=True,
            array_name="refPoints2")
        if refPoints2.shape[1] != 3:
            raise TypeError('refPoints2 should be an Nx3 array')

        # keeping the below syntax seems to be crucial for passing unit tests
        cdef np.ndarray[float, ndim=1] l_refPoints1 = np.copy(
            np.ascontiguousarray(refPoints1.flatten()))
        cdef np.ndarray[float, ndim=1] l_refPoints2 = np.copy(
            np.ascontiguousarray(refPoints2.flatten()))
        cdef unsigned int nRef1 = <unsigned int> refPoints1.shape[0]
        cdef unsigned int nRef2 = <unsigned int> refPoints2.shape[0]

        if nRef1 != nRef2:
            raise ValueError(
                ("The number of vectors in refPoints1 must MATCH the number of"
                    "vectors in refPoints2"))

        cdef float min_rmsd = -1
        # keeping the below syntax seems to be crucial for passing unit tests
        cdef map[unsigned int, unsigned int] results_map = \
            self.thisptr.minimizeRMSD(
                <vec3[float]*> &l_refPoints1[0],
                <vec3[float]*> &l_refPoints2[0],
                nRef1, min_rmsd, registration)
        cdef np.ndarray[float, ndim=2] rot_refPoints2 = np.reshape(
            l_refPoints2, (nRef2, 3))
        return [min_rmsd, rot_refPoints2, results_map]

    @property
    def clusters(self):
        cdef unsigned int * clusters = self.thisptr.getClusters().get()
        cdef np.npy_intp nbins[1]
        # this is the correct number
        nbins[0] = <np.npy_intp> self.thisptr.getNP()
        cdef np.ndarray[np.uint32_t, ndim=1] result = \
            np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32,
                                         <void*> clusters)
        return result

    def getClusters(self):
        warnings.warn("The getClusters function is deprecated in favor "
                      "of the clusters class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.clusters

    def getEnvironment(self, i):
        """Returns the set of vectors defining the environment indexed by i.

        Args:
            i (unsigned int): Environment index.

        Returns:
            :math:`\\left(N_{neighbors}, 3\\right)` :class:`numpy.ndarray`:
            The array of vectors.
        """
        cdef vec3[float] * environment = self.thisptr.getEnvironment(i).get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp> self.thisptr.getMaxNumNeighbors()
        nbins[1] = 3
        cdef np.ndarray[float, ndim=2] result = \
            np.PyArray_SimpleNewFromData(2, nbins, np.NPY_FLOAT32,
                                         <void*> environment)
        return result

    @property
    def tot_environment(self):
        cdef vec3[float] * tot_environment = \
            self.thisptr.getTotEnvironment().get()
        cdef np.npy_intp nbins[3]
        nbins[0] = <np.npy_intp> self.thisptr.getNP()
        nbins[1] = <np.npy_intp> self.thisptr.getMaxNumNeighbors()
        nbins[2] = 3
        cdef np.ndarray[float, ndim=3] result = \
            np.PyArray_SimpleNewFromData(3, nbins, np.NPY_FLOAT32,
                                         <void*> tot_environment)
        return result

    def getTotEnvironment(self):
        warnings.warn("The getTotEnvironment function is deprecated in favor "
                      "of the tot_environment class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.tot_environment

    @property
    def num_particles(self):
        cdef unsigned int np = self.thisptr.getNP()
        return np

    def getNP(self):
        warnings.warn("The getNP function is deprecated in favor "
                      "of the num_particles class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.num_particles

    @property
    def num_clusters(self):
        cdef unsigned int num_clust = self.thisptr.getNumClusters()
        return num_clust

    def getNumClusters(self):
        warnings.warn("The getNumClusters function is deprecated in favor "
                      "of the num_clusters class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.num_clusters


cdef class Pairing2D:
    """Compute pairs for the system of particles.

    .. moduleauthor:: Eric Harper <harperic@umich.edu>

    .. deprecated:: 0.8.2
       Use :py:mod:`freud.bond` instead.

    Args:
        rmax (float):
            Distance over which to calculate.
        k (unsigned int):
            Number of neighbors to search.
        compDotTol (float):
            Value of the dot product below which a pair is determined.

    Attributes:
        match (:math:`\\left(N_{particles}\\right)` :class:`numpy.ndarray`):
            The match.
        pair (:math:`\\left(N_{particles}\\right)` :class:`numpy.ndarray`):
            The pair.
        box (:py:class:`freud.box.Box`):
            Box used in the calculation.
    """
    def __cinit__(self, rmax, k, compDotTol):
        warnings.warn("This class is deprecated, use freud.bond instead!",
                      FreudDeprecationWarning)
        self.thisptr = new freud._environment.Pairing2D(rmax, k, compDotTol)
        self.rmax = rmax
        self.num_neigh = k

    def __dealloc__(self):
        del self.thisptr

    def compute(self, box, points, orientations, compOrientations, nlist=None):
        """Calculates the correlation function and adds to the current
        histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Reference points to calculate the local density.
            orientations ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                Orientations to use in computation.
            compOrientations ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                Possible orientations to check for bonds.
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa: E501
        cdef freud.box.Box b = freud.common.convert_box(box)
        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True, array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        orientations = freud.common.convert_array(
            orientations, 1, dtype=np.float32, contiguous=True,
            array_name="orientations")

        compOrientations = freud.common.convert_array(
            compOrientations, 2, dtype=np.float32, contiguous=True,
            array_name="compOrientations")

        cdef np.ndarray[float, ndim=2] l_points = points
        cdef np.ndarray[float, ndim=2] l_compOrientations = compOrientations
        cdef np.ndarray[float, ndim=1] l_orientations = orientations
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef unsigned int nO = <unsigned int> compOrientations.shape[1]

        defaulted_nlist = freud.locality.make_default_nlist_nn(
            b, points, points, self.num_neigh, nlist, True, self.rmax)
        cdef freud.locality.NeighborList nlist_ = defaulted_nlist[0]

        self.thisptr.compute(
            dereference(b.thisptr), nlist_.get_ptr(),
            <vec3[float]*> l_points.data, <float*> l_orientations.data,
            <float*> l_compOrientations.data, nP, nO)
        return self

    @property
    def match(self):
        cdef unsigned int * match = self.thisptr.getMatch().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp> self.thisptr.getNumParticles()
        cdef np.ndarray[np.uint32_t, ndim=1] result = \
            np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32,
                                         <void*> match)
        return result

    def getMatch(self):
        warnings.warn("The getMatch function is deprecated in favor "
                      "of the match class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.match

    @property
    def pair(self):
        cdef unsigned int * pair = self.thisptr.getPair().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp> self.thisptr.getNumParticles()
        cdef np.ndarray[np.uint32_t, ndim=1] result = \
            np.PyArray_SimpleNewFromData(1, nbins, np.NPY_UINT32, <void*> pair)
        return result

    def getPair(self):
        warnings.warn("The getPair function is deprecated in favor "
                      "of the pair class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.pair

    @property
    def box(self):
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    def getBox(self):
        warnings.warn("The getBox function is deprecated in favor "
                      "of the box class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.box


cdef class AngularSeparation:
    """Calculates the minimum angles of separation between particles and
    references.

    .. moduleauthor:: Erin Teich <erteich@umich.edu>
    .. moduleauthor:: Andrew Karas <askaras@umich.edu>

    Args:
        rmax (float):
            Cutoff radius for cell list and clustering algorithm. Values near
            the first minimum of the RDF are recommended.
        n (int):
            The number of neighbors.

    Attributes:
        nlist (:class:`freud.locality.NeighborList`):
            The neighbor list.
        n_p (unsigned int):
            The number of particles used in computing the last set.
        n_ref (unsigned int):
            The number of reference particles used in computing the neighbor
            angles.
        n_global (unsigned int):
            The number of global orientations to check against.
        neighbor_angles ((:math:`\\left(N_{particles}\\timesN_{neighbors}, \\right)` :class:`numpy.ndarray`):
            The neighbor angles in radians. **This field is only populated
            after :py:meth`~.computeNeighbor` is called.** The angles
            are stored in the order of the neighborlist object.
        global_angles (:math:`\\left(N_{global}, N_{particles} \\right)` :class:`numpy.ndarray`):
            The global angles in radians. **This field is only populated after
            :py:meth:`.computeGlobal` is called.** The angles
            are stored in the order of the neighborlist object.

    .. todo Need to figure out what happens if you use a neighborlist with
            strict_cut=True
    """  # noqa: E501
    def __cinit__(self, rmax, n):
        self.thisptr = new freud._environment.AngularSeparation()
        self.rmax = rmax
        self.num_neigh = int(n)
        self.nlist_ = None

    def __dealloc__(self):
        del self.thisptr

    @property
    def nlist(self):
        return self.nlist_

    def computeNeighbor(self, box, ref_ors, ors, ref_points, points,
                        equiv_quats, nlist=None):
        """Calculates the minimum angles of separation between ref_ors and ors,
        checking for underlying symmetry as encoded in equiv_quats. The result
        is stored in the :code:`neighbor_angles` class attribute.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            ref_ors ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                Reference orientations used to calculate the order parameter.
            ors ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Orientations used to calculate the order parameter.
            ref_points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate the order parameter.
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Points used to calculate the order parameter.
            equiv_quats ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`, optional):
                The set of all equivalent quaternions that takes the particle
                as it is defined to some global reference orientation.
                Important: :code:`equiv_quats` must include both :math:`q` and
                :math:`-q`, for all included quaternions.
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa: E501
        cdef freud.box.Box b = freud.common.convert_box(box)
        ref_points = freud.common.convert_array(
            ref_points, 2, dtype=np.float32, contiguous=True,
            array_name="ref_points")
        if ref_points.shape[1] != 3:
            raise TypeError('ref_points should be an Nx3 array')

        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True, array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        ref_ors = freud.common.convert_array(
            ref_ors, 2, dtype=np.float32, contiguous=True,
            array_name="ref_ors")
        if ref_ors.shape[1] != 4:
            raise TypeError('ref_ors should be an Nx4 array')

        ors = freud.common.convert_array(
            ors, 2, dtype=np.float32, contiguous=True, array_name="ors")
        if ors.shape[1] != 4:
            raise TypeError('ors should be an Nx4 array')

        equiv_quats = freud.common.convert_array(
            equiv_quats, 2, dtype=np.float32, contiguous=True,
            array_name="equiv_quats")
        if equiv_quats.shape[1] != 4:
            raise TypeError('equiv_quats should be an N_equiv x 4 array')

        defaulted_nlist = freud.locality.make_default_nlist_nn(
            b, ref_points, points, self.num_neigh, nlist, None, self.rmax)
        cdef freud.locality.NeighborList nlist_ = defaulted_nlist[0]
        self.nlist_ = nlist_

        cdef np.ndarray[float, ndim=2] l_ref_ors = ref_ors
        cdef np.ndarray[float, ndim=2] l_ors = ors
        cdef np.ndarray[float, ndim=2] l_equiv_quats = equiv_quats

        cdef unsigned int nRef = <unsigned int> ref_ors.shape[0]
        cdef unsigned int nP = <unsigned int> ors.shape[0]
        cdef unsigned int nEquiv = <unsigned int> equiv_quats.shape[0]

        with nogil:
            self.thisptr.computeNeighbor(
                nlist_.get_ptr(),
                <quat[float]*> l_ref_ors.data,
                <quat[float]*> l_ors.data,
                <quat[float]*> l_equiv_quats.data,
                nRef, nP, nEquiv)
        return self

    def computeGlobal(self, global_ors, ors, equiv_quats):
        """Calculates the minimum angles of separation between
        :code:`global_ors` and :code:`ors`, checking for underlying symmetry as
        encoded in :code`equiv_quats`. The result is stored in the
        :code:`global_angles` class attribute.


        Args:
            ors ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Orientations to calculate the order parameter.
            global_ors ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                Reference orientations to calculate the order parameter.
            equiv_quats ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                The set of all equivalent quaternions that takes the particle
                as it is defined to some global reference orientation.
                Important: :code:`equiv_quats` must include both :math:`q` and
                :math:`-q`, for all included quaternions.
        """
        global_ors = freud.common.convert_array(
            global_ors, 2, dtype=np.float32, contiguous=True,
            array_name="global_ors")
        if global_ors.shape[1] != 4:
            raise TypeError('global_ors should be an Nx4 array')

        ors = freud.common.convert_array(
            ors, 2, dtype=np.float32, contiguous=True,
            array_name="ors")
        if ors.shape[1] != 4:
            raise TypeError('ors should be an Nx4 array')

        equiv_quats = freud.common.convert_array(
            equiv_quats, 2, dtype=np.float32, contiguous=True,
            array_name="equiv_quats")
        if equiv_quats.shape[1] != 4:
            raise TypeError('equiv_quats should be an N_equiv x 4 array')

        cdef np.ndarray[float, ndim=2] l_global_ors = global_ors
        cdef np.ndarray[float, ndim=2] l_ors = ors
        cdef np.ndarray[float, ndim=2] l_equiv_quats = equiv_quats

        cdef unsigned int nGlobal = <unsigned int> global_ors.shape[0]
        cdef unsigned int nP = <unsigned int> ors.shape[0]
        cdef unsigned int nEquiv = <unsigned int> equiv_quats.shape[0]

        with nogil:
            self.thisptr.computeGlobal(
                <quat[float]*> l_global_ors.data,
                <quat[float]*> l_ors.data,
                <quat[float]*> l_equiv_quats.data,
                nGlobal, nP, nEquiv)
        return self

    @property
    def neighbor_angles(self):
        cdef float * neigh_ang = self.thisptr.getNeighborAngles().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp> len(self.nlist)
        cdef np.ndarray[float, ndim=1] result = \
            np.PyArray_SimpleNewFromData(1, nbins, np.NPY_FLOAT32,
                                         <void*> neigh_ang)
        return result

    def getNeighborAngles(self):
        warnings.warn("The getNeighborAngles function is deprecated in favor "
                      "of the neighbor_angles class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.neighbor_angles

    @property
    def global_angles(self):
        cdef float * global_ang = self.thisptr.getGlobalAngles().get()
        cdef np.npy_intp nbins[2]
        nbins[0] = <np.npy_intp> self.thisptr.getNP()
        nbins[1] = <np.npy_intp> self.thisptr.getNglobal()
        cdef np.ndarray[float, ndim=2] result = \
            np.PyArray_SimpleNewFromData(2, nbins, np.NPY_FLOAT32,
                                         <void*> global_ang)
        return result

    def getGlobalAngles(self):
        warnings.warn("The getGlobalAngles function is deprecated in favor "
                      "of the global_angles class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.global_angles

    @property
    def n_p(self):
        cdef unsigned int np = self.thisptr.getNP()
        return np

    def getNP(self):
        warnings.warn("The getNP function is deprecated in favor "
                      "of the n_p class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.n_p

    @property
    def n_ref(self):
        cdef unsigned int nref = self.thisptr.getNref()
        return nref

    def getNReference(self):
        warnings.warn("The getNReference function is deprecated in favor "
                      "of the n_ref class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.n_ref

    @property
    def n_global(self):
        cdef unsigned int nglobal = self.thisptr.getNglobal()
        return nglobal

    def getNGlobal(self):
        warnings.warn("The getNGlobal function is deprecated in favor "
                      "of the n_global class attribute and will be "
                      "removed in a future version of freud.",
                      FreudDeprecationWarning)
        return self.n_global


cdef class LocalBondProjection:
    """Calculates the maximal projection of nearest neighbor bonds for each
    particle onto some set of reference vectors, defined in the particles'
    local reference frame.

    .. moduleauthor:: Erin Teich <erteich@umich.edu>

    Args:
        rmax (float):
            Cutoff radius.
        num_neighbors (unsigned int):
            The number of neighbors.

    Attributes:
        projections ((:math:`\\left(N_{reference}, N_{neighbors}, N_{projection\_vecs} \\right)` :class:`numpy.ndarray`):
            The projection of each bond between reference particles and their
            neighbors onto each of the projection vectors.
        normed_projections ((:math:`\\left(N_{reference}, N_{neighbors}, N_{projection\_vecs} \\right)` :class:`numpy.ndarray`)
            The normalized projection of each bond between reference particles
            and their neighbors onto each of the projection vectors.
        num_reference_particles (int):
            The number of reference points used in the last calculation.
        num_particles (int):
            The number of points used in the last calculation.
        num_proj_vectors (int):
            The number of projection vectors used in the last calculation.
        box (:class:`freud.box.Box`):
            The box used in the last calculation.
    """  # noqa: E501

    cdef freud._environment.LocalBondProjection * thisptr
    cdef rmax
    cdef num_neigh
    cdef nlist_

    def __cinit__(self, rmax, num_neigh):
        self.thisptr = new freud._environment.LocalBondProjection()
        self.rmax = rmax
        self.num_neigh = int(num_neigh)
        self.nlist_ = None

    def __dealloc__(self):
        del self.thisptr

    @property
    def nlist(self):
        return self.nlist_

    def compute(self, box, proj_vecs, ref_points, ref_ors, points=None,
                equiv_quats=np.array([[1, 0, 0, 0]]), nlist=None):
        """Calculates the maximal projections of nearest neighbor bonds
        (between :code:`ref_points` and :code:`points`) onto the set of
        reference vectors :code:`proj_vecs`, defined in the local reference
        frames of the :code:`ref_points` as defined by the orientations
        :code:`ref_ors`. This computation accounts for the underlying
        symmetries of the reference frame as encoded in :code:`equiv_quats`.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            proj_vecs ((:math:`N_{vectors}`, 3) :class:`numpy.ndarray`):
                The set of reference vectors, defined in the reference
                particles' reference frame, to calculate maximal local bond
                projections onto.
            ref_points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`):
                Reference points used in the calculation.
            ref_ors ((:math:`N_{particles}`, 4) :class:`numpy.ndarray`):
                Reference orientations used in the calculation.
            points ((:math:`N_{particles}`, 3) :class:`numpy.ndarray`, optional):
                Points (neighbors of :code:`ref_points`) used in the
                calculation. Uses :code:`ref_points` if not provided or
                :code:`None`.
            equiv_quats ((:math:`N_{quats}`, 4) :class:`numpy.ndarray`, optional):
                The set of all equivalent quaternions that takes the particle
                as it is defined to some global reference orientation. Note
                that this does not need to include both :math:`q` and
                :math:`-q`, since :math:`q` and :math:`-q` effect the same
                rotation on vectors. Defaults to an identity quaternion.
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa: E501
        cdef freud.box.Box b = freud.common.convert_box(box)
        ref_points = freud.common.convert_array(
            ref_points, 2, dtype=np.float32, contiguous=True,
            array_name="ref_points")
        if ref_points.shape[1] != 3:
            raise TypeError('ref_points should be an Nx3 array')

        ref_ors = freud.common.convert_array(
            ref_ors, 2, dtype=np.float32, contiguous=True,
            array_name="ref_ors")
        if ref_ors.shape[1] != 4:
            raise TypeError('ref_ors should be an Nx4 array')

        if points is None:
            points = ref_points
        points = freud.common.convert_array(
            points, 2, dtype=np.float32, contiguous=True,
            array_name="points")
        if points.shape[1] != 3:
            raise TypeError('points should be an Nx3 array')

        equiv_quats = freud.common.convert_array(
            equiv_quats, 2, dtype=np.float32, contiguous=True,
            array_name="equiv_quats")
        if equiv_quats.shape[1] != 4:
            raise TypeError('equiv_quats should be an N_equiv x 4 array')

        proj_vecs = freud.common.convert_array(
            proj_vecs, 2, dtype=np.float32, contiguous=True,
            array_name="proj_vecs")
        if proj_vecs.shape[1] != 3:
            raise TypeError('proj_vecs should be an Nx3 array')

        defaulted_nlist = freud.locality.make_default_nlist_nn(
            box, ref_points, points, self.num_neigh, nlist, None, self.rmax)
        cdef freud.locality.NeighborList nlist_ = defaulted_nlist[0]
        self.nlist_ = nlist_

        cdef np.ndarray[float, ndim=2] l_ref_points = ref_points
        cdef np.ndarray[float, ndim=2] l_ref_ors = ref_ors
        cdef np.ndarray[float, ndim=2] l_points = points
        cdef np.ndarray[float, ndim=2] l_equiv_quats = equiv_quats
        cdef np.ndarray[float, ndim=2] l_proj_vecs = proj_vecs

        cdef unsigned int nRef = <unsigned int> ref_points.shape[0]
        cdef unsigned int nP = <unsigned int> points.shape[0]
        cdef unsigned int nEquiv = <unsigned int> equiv_quats.shape[0]
        cdef unsigned int nProj = <unsigned int> proj_vecs.shape[0]

        with nogil:
            self.thisptr.compute(
                dereference(b.thisptr),
                nlist_.get_ptr(),
                <vec3[float]*> l_points.data,
                <vec3[float]*> l_ref_points.data,
                <quat[float]*> l_ref_ors.data,
                <quat[float]*> l_equiv_quats.data,
                <vec3[float]*> l_proj_vecs.data,
                nP, nRef, nEquiv, nProj)
        return self

    @property
    def projections(self):
        cdef float * proj = self.thisptr.getProjections().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp> len(self.nlist) * self.thisptr.getNproj()
        cdef np.ndarray[float, ndim=1] result = \
            np.PyArray_SimpleNewFromData(
                1, nbins, np.NPY_FLOAT32, <void*> proj)
        return result

    @property
    def normed_projections(self):
        cdef float * proj = self.thisptr.getNormedProjections().get()
        cdef np.npy_intp nbins[1]
        nbins[0] = <np.npy_intp> len(self.nlist) * self.thisptr.getNproj()
        cdef np.ndarray[float, ndim=1] result = \
            np.PyArray_SimpleNewFromData(
                1, nbins, np.NPY_FLOAT32, <void*> proj)
        return result

    @property
    def num_particles(self):
        cdef unsigned int np = self.thisptr.getNP()
        return np

    @property
    def num_reference_particles(self):
        cdef unsigned int nref = self.thisptr.getNref()
        return nref

    @property
    def num_proj_vectors(self):
        cdef unsigned int nproj = self.thisptr.getNproj()
        return nproj

    @property
    def box(self):
        return freud.box.BoxFromCPP(<freud._box.Box> self.thisptr.getBox())