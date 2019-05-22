import numpy as np
import numpy.testing as npt
import freud
import unittest
import warnings
import util


class TestSteinhardt(unittest.TestCase):
    def test_shape(self):
        N = 1000

        box = freud.box.Box.cube(10)
        np.random.seed(0)
        positions = np.random.uniform(-box.Lx/2, box.Lx/2,
                                      size=(N, 3)).astype(np.float32)

        positions.flags['WRITEABLE'] = False
        comp = freud.order.Steinhardt(box, 1.5, 6)
        comp.compute(positions)

        npt.assert_equal(comp.St.shape[0], N)

    def test_identical_environments_Ql(self):

        (box, positions) = util.make_fcc(4, 4, 4)

        comp = freud.order.Steinhardt(box, 1.5, 6)

        comp.compute(positions)
        npt.assert_almost_equal(np.average(comp.St), 0.57452422, decimal=5)
        npt.assert_almost_equal(comp.St, comp.St[0])

        comp = freud.order.Steinhardt(box, 1.5, 6, average=True)

        comp.compute(positions)
        npt.assert_almost_equal(np.average(comp.St), 0.57452422, decimal=5)
        npt.assert_almost_equal(comp.St, comp.St[0])

        comp = freud.order.Steinhardt(box, 1.5, 6, norm=True)

        comp.compute(positions)
        npt.assert_almost_equal(np.average(comp.St), 0.57452422, decimal=5)
        npt.assert_almost_equal(comp.St, comp.St[0])

        comp = freud.order.Steinhardt(box, 1.5, 6, average=True, norm=True)

        comp.compute(positions)
        npt.assert_almost_equal(np.average(comp.St), 0.57452422, decimal=5)
        npt.assert_almost_equal(comp.St, comp.St[0])

    def test_identical_environments_Wl(self):
        (box, positions) = util.make_fcc(4, 4, 4)
        
        comp = freud.order.Steinhardt(box, 1.5, 6, Wl=True)
        comp.compute(positions)
        self.assertTrue(np.isclose(
            np.real(np.average(comp.St)), -0.002626035, atol=1e-5))
        self.assertTrue(np.allclose(comp.St, comp.St[0]))

        comp = freud.order.Steinhardt(box, 1.5, 6, Wl=True,
                                      average=True)
        comp.compute(positions)
        self.assertTrue(np.isclose(
            np.real(np.average(comp.St)), -0.002626035, atol=1e-5))
        self.assertTrue(np.allclose(comp.St, comp.St[0]))

        comp = freud.order.Steinhardt(box, 1.5, 6, Wl=True,
                                      norm=True)
        comp.compute(positions)
        self.assertTrue(np.isclose(
            np.real(np.average(comp.St)), -0.002626035, atol=1e-5))
        self.assertTrue(np.allclose(comp.St, comp.St[0]))

        comp = freud.order.Steinhardt(box, 1.5, 6, Wl=True,
                                      average=True, norm=True)

        comp.compute(positions)
        self.assertTrue(np.isclose(
            np.real(np.average(comp.St)), -0.002626035, atol=1e-5))
        self.assertTrue(np.allclose(comp.St, comp.St[0]))

        self.assertEqual(box, comp.box)

        self.assertEqual(len(positions), comp.num_particles)



if __name__ == '__main__':
    unittest.main()
