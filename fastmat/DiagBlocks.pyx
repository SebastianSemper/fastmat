# -*- coding: utf-8 -*-
#cython: boundscheck=False, wraparound=False
'''
  fastmat/DiagBlocks.py
 -------------------------------------------------- part of the fastmat package

  DiagBlocks matrix.


  Author      : sempersn
  Introduced  : 2017-10-06
 ------------------------------------------------------------------------------

   Copyright 2016 Sebastian Semper, Christoph Wagner
       https://www.tu-ilmenau.de/ems/

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

 ------------------------------------------------------------------------------

  TODO:
    - DiagBlocks should simply skip all Zero Matrices (flag them as "None")?
'''
import numpy as np
cimport numpy as np

from .Matrix cimport Matrix


################################################################################
################################################## class DiagBlocks
cdef class DiagBlocks(Matrix):

    ############################################## class methods
    def __init__(self, tenDiags):
        '''Initialize Matrix instance with a list of child matrices'''

        self._numDiagsN = tenDiags.shape[0]
        self._numDiagsM = tenDiags.shape[1]
        self._numDiagsSize = tenDiags.shape[2]

        cdef intsize numN = self._numDiagsN * self._numDiagsSize
        cdef intsize numM = self._numDiagsM * self._numDiagsSize

        self._tenDiags = np.copy(tenDiags)

        dataType = tenDiags.dtype

        # set properties of matrix
        self._initProperties(
            numN, numM, dataType,
            cythonCall=True,
            widenInputDatatype=True
        )

    ############################################## class property override
    cpdef tuple _getComplexity(self):

        return (0, 0)

    ############################################## class forward / backward
    cpdef _forwardC(
        self,
        np.ndarray arrX,
        np.ndarray arrRes,
        ftype typeX,
        ftype typeRes
    ):
        '''Calculate the forward transform of this matrix'''
        arrRes[:] = np.einsum(
            'nmz,zmk -> znk',
            self._tenDiags,
            arrX.reshape((-1, self._numDiagsM, arrX.shape[1]), order='F')
        ).reshape((-1, arrX.shape[1]), order='F')

    cpdef _backwardC(
        self,
        np.ndarray arrX,
        np.ndarray arrRes,
        ftype typeX,
        ftype typeRes
    ):
        '''Calculate the backward transform of this matrix'''
        arrRes[:] = np.einsum(
            'mnz,zmk -> znk',
            self._tenDiags.conj(),
            arrX.reshape((-1, self._numDiagsM, arrX.shape[1]), order='F')
        ).reshape((-1, arrX.shape[1]), order='F')

    ############################################## class reference
    cpdef np.ndarray _reference(self):
        '''
        Return an explicit representation of the matrix without using
        any fastmat code.
        '''
        cdef np.ndarray arrRes

        arrRes = np.zeros((self.numN, self.numM), dtype=self.dtype)

        for nn in range(self._numDiagsN):
            for mm in range(self._numDiagsM):
                arrRes[
                    nn *self._numDiagsSize:
                    (nn +1) *self._numDiagsSize,
                    mm *self._numDiagsSize:
                    (mm +1) *self._numDiagsSize
                ] = np.diag(self._tenDiags[nn, mm, :])

        return arrRes

    ############################################## class inspection, QM
    def _getTest(self):
        from .inspect import TEST, dynFormat
        return {
            TEST.COMMON: {
                'size'          : 4,
                TEST.NUM_N      : 32,
                TEST.NUM_M      : 32,
                'mType'        : TEST.Permutation(TEST.ALLTYPES),
                'arr'          : TEST.ArrayGenerator({
                    TEST.DTYPE  : 'mType',
                    TEST.SHAPE  : (8, 8, 4)
                }),
                TEST.INITARGS   : (lambda param : [param['arr']()]),
                TEST.OBJECT     : DiagBlocks,
                TEST.NAMINGARGS : dynFormat("(%dx%d) each",
                                            'size', 'size')
            },
            TEST.CLASS: {},
            TEST.TRANSFORMS: {}
        }

    def _getBenchmark(self):
        from .inspect import BENCH

        return {
            BENCH.FORWARD: {
                BENCH.FUNC_GEN  : (lambda c: DiagBlocks(
                    np.random.randn(c, c, 64)
                )),
                BENCH.FUNC_SIZE : (lambda c: 64 * c)
            },
            BENCH.OVERHEAD: {
                BENCH.FUNC_GEN  : (lambda c: DiagBlocks(
                    np.random.randn(2 ** c, 2 ** c, c)
                )),
                BENCH.FUNC_SIZE : (lambda c: 2 ** c * c)
            }
        }

    def _getDocumentation(self):
        from .inspect import DOC
        return DOC.SUBSECTION(
            r'Diagonal Block Matrix (\texttt{fastmat.DiagBlocks})',
            DOC.SUBSUBSECTION(
                'Definition and Interface',
                r"""
For given $n,m \in \N$ this class allows to define a block matrix $\bm M \in
\C^{nm \times nm}$, where each block is a diagonal matrix $\bm D_{ij} \in
\C^{m \times m}$. This obviously allows efficient storage and computations.""",
                DOC.SNIPPET('# import the package',
                            'import fastmat as fm',
                            '',
                            '# define the sizes',
                            'n,m = 2,3'
                            '',
                            '# define the diagonals',
                            'd = np.random.randn(',
                            '       n,',
                            '       n,',
                            '       m)',
                            '',
                            '# define the block',
                            '# matrix diagonal-wise',
                            'M = fm.DiagBlocks(d)',
                            caption=r"""
We have randomly drawn the defining elements $\bm d$ from a standard Gaussian
distribution, which results in
\[
    \bm M =
        \left(\begin{array}{cccccc}
                d_{1,1,1} & & & d_{1,2,1} & & \\
                & d_{1,1,2} & & & d_{1,2,2} & \\
                & & d_{1,1,3} & & & d_{1,2,3} \\
                d_{2,1,1} & & & d_{2,2,1} & & \\
                & d_{2,1,2} & & & d_{2,2,2} & \\
                & & d_{2,1,3} & & & d_{2,2,3} \\
              \end{array}\right).\]""")
            ),
            DOC.SUBSUBSECTION(
                'Performance Benchmarks',
                DOC.PLOTFORWARD(),
                DOC.PLOTFORWARDMEMORY(),
                DOC.PLOTOVERHEAD(doc=r"""
$\bm B = \begin{pmatrix}
    \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k} \\
    \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k} \\
    \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k} \\
    \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k} & \bm I_{2^k}
\end{pmatrix}$, $n = 2^{k+2}$ for $k \in \N$""")
            )
        )
