# -*- coding: utf-8 -*-
'''
  fastmat/Product.py
 -------------------------------------------------- part of the fastmat package

  Product of fastmat matrices.


  Author      : wcw, sempersn
  Introduced  : 2016-04-08
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
'''
import numpy as np
cimport numpy as np

from .Matrix cimport Matrix
from .Transpose cimport *
from .helpers.cmath cimport _conjugate
from .helpers.types cimport *


################################################################################
################################################## class Product
cdef class Product(Matrix):

    ############################################## class properties
    # content - Property (read-only)
    # Return the content of the product
    property content:
        def __get__(self):
            lst = [self._scalar] if self._scalar != 1 else []
            return lst + list(self._content)

    ############################################## class methods
    def __init__(self, *matrices, **options):
        '''Initialize Matrix instance'''

        # evaluate options passed to Product
        debug = options.get('debug', False)

        # initialize product content to [1]
        lstFactors = []
        self._scalar = np.int8(1)

        # determine data type of matrix: store datatype in immutable object to
        # allow access from within subfunctions (python2/3 compatible)
        datatype = [self._scalar.dtype]

        def __promoteType(dtype):
            datatype[0] = np.promote_types(datatype[0], dtype)

        # add all product terms, direct and nested
        def __addFactors(factors):
            for factor in factors:
                if np.isscalar(factor):
                    # explicit type promotion: avoid type shortening of scalars
                    __promoteType(np.array(factor).dtype)
                    self._scalar = np.inner(self._scalar, factor)
                    continue

                if not isinstance(factor, Matrix):
                    raise TypeError("Product has non-fastmat-matrix terms.")

                if isinstance(factor, Product):
                    __addFactors(factor.content)
                else:
                    # store fastmat-matrix-content: determine data type
                    # -> promotion of factor types
                    __promoteType(factor.dtype)
                    lstFactors.append(factor)
        __addFactors(matrices)
        dtype = datatype[0]

        # handle type expansion with default depending on matrix type
        # default: expand small types due to accumulation during transforms
        # skip by specifying `typeExpansion=None` or override with `~=...`
        typeExpansion = options.get('typeExpansion', safeTypeExpansion(dtype))
        dtype = (dtype if typeExpansion is None
                 else np.promote_types(dtype, typeExpansion))

        # sanity check of the supplied amount of product terms
        if len(lstFactors) < 1:
            raise ValueError("Product has no terms.")

        # iterate elements and check if their numN fit the previous numM
        cdef intsize numN = lstFactors[0].numN
        cdef intsize numM = lstFactors[0].numM
        cdef int ii
        for ii in range(1, len(lstFactors)):
            factor = lstFactors[ii]
            if factor.numN != numM:
                raise ValueError(
                    ("Dimensions of product factor %d [%dx%d] " +
                     "do not match.") %(ii, numN, numM))
            numM = factor.numM

        # force scalar datatype to match matrix datatype (calculation accuracy)
        self._scalar = self._scalar.astype(dtype)

        # also, make factor list immutable
        self._content = tuple(lstFactors)

        # set properties of matrix
        self._initProperties(numN, numM, dtype)

        if debug:
            print("fastmat.Product instance %12x containing:" %(id(self)))
            if self._scalar != 1:
                print("  [0]: scalar %s" %(self._scalar))
            for ii, factor in enumerate(lstFactors):
                print("  [%d]: %s" %(ii, factor.__repr__()))

    ############################################## class property override
    cpdef np.ndarray _getCol(self, intsize idx):
        # regular product except the last term is just term._getCol
        cdef int cnt = len(self._content)
        cdef int ii                     # index (0 .. cnt - 1)
        cdef int iii = cnt - 1          # index (cnt - 1 .. 0)
        cdef np.ndarray arrRes = self._content[iii].getCol(idx)

        # use inner for element-wise scalar mul as inner does type promotion
        if self._scalar != 1:
            arrRes = np.inner(arrRes, self._scalar)
        else:
            arrRes = arrRes.astype(np.promote_types(arrRes.dtype, self.dtype))

        for ii in range(1, cnt):
            iii = cnt - 1 - ii
            arrRes = self._content[iii].forward(arrRes)

        return arrRes

    cpdef np.ndarray _getRow(self, intsize idx):
        # regular product w/ backward except the last term is just term._getRow
        cdef int cnt = len(self._content)
        cdef int ii = 0
        cdef np.ndarray arrRes = _conjugate(self._content[ii].getRow(idx))

        # use inner for element-wise scalar mul as inner does type promotion
        if self._scalar != 1:
            if np.iscomplex(self._scalar):
                arrRes = np.inner(arrRes, self._scalar.conjugate())
            else:
                arrRes = np.inner(arrRes, self._scalar)
        else:
            arrRes = arrRes.astype(np.promote_types(arrRes.dtype, self.dtype))

        for ii in range(1, cnt):
            arrRes = self._content[ii].backward(arrRes)

        # don't forget to return the conjugate as we use the backward
        return _conjugate(arrRes)

    ############################################## class forward / backward
    cpdef np.ndarray _forward(self, np.ndarray arrX):
        '''Calculate the forward transform of this matrix'''

        cdef int cnt = len(self._content)
        cdef int ii                     # index (0 .. cnt - 1)
        cdef int iii = cnt - 1          # index (cnt - 1 .. 0)
        cdef np.ndarray arrRes = arrX

        # use inner for element-wise scalar mul as inner does type promotion
        if self._scalar != 1:
            arrRes = np.inner(arrRes, self._scalar)
        else:
            arrRes = arrRes.astype(np.promote_types(arrRes.dtype, self.dtype))

        for ii in range(0, cnt):
            iii = cnt - 1 - ii
            arrRes = self._content[iii].forward(arrRes)

        return arrRes

    cpdef np.ndarray _backward(self, np.ndarray arrX):
        '''Calculate the backward transform of this matrix'''

        cdef int cnt = len(self._content)
        cdef int ii
        cdef np.ndarray arrRes = arrX

        # use inner for element-wise scalar mul as inner does type promotion
        if self._scalar != 1:
            if np.iscomplex(self._scalar):
                arrRes = np.inner(arrRes, self._scalar.conjugate())
            else:
                arrRes = np.inner(arrRes, self._scalar)
        else:
            arrRes = arrRes.astype(np.promote_types(arrRes.dtype, self.dtype))

        for ii in range(0, cnt):
            arrRes = self._content[ii].backward(arrRes)

        return arrRes

    ############################################## class reference
    cpdef np.ndarray _reference(self):
        '''
        Return an explicit representation of the matrix without using
        any fastmat code.
        '''
        cdef ii, cnt = len(self._content)
        cdef Matrix term
        cdef np.ndarray arrRes

        dtype = np.promote_types(np.float64, self.dtype)

        arrRes = np.inner(
            self._content[cnt - 1].reference(), self._scalar.astype(dtype))

        for ii in range(1, cnt):
            term = self._content[cnt - ii - 1]
            arrRes = term.reference().dot(arrRes)

        return arrRes

    def _forwardReferenceInit(self):
        self._forwardReferenceMatrix = []
        for ii, term in enumerate(self._content):
            self._forwardReferenceMatrix.append(term.reference())

    def _forwardReference(self, arrX):
        '''Calculate the forward transform by non-fastmat means.'''

        # check if operation list initialized. If not, then do it!
        if not isinstance(self._forwardReferenceMatrix, list):
            self._forwardReferenceInit()

        # perform operations list
        arrRes = arrX
        for ii in range(len(self._content), 0, -1):
            arrRes = self._forwardReferenceMatrix[ii - 1].dot(arrRes)

        return arrRes


################################################################################
################################################################################
from .helpers.unitInterface import *

################################################### Testing
test = {
    NAME_COMMON: {
        TEST_NUM_N: 7,
        TEST_NUM_M: Permutation([10, TEST_NUM_N]),
        'mType1': Permutation(typesAll),
        'mType2': Permutation(typesSmallIFC),
        'sType': Permutation(typesAll),
        'arr1': ArrayGenerator({
            NAME_DTYPE  : 'mType1',
            NAME_SHAPE  : (TEST_NUM_N, TEST_NUM_M)
            #            NAME_CENTER : 2,
        }),
        'arr2': ArrayGenerator({
            NAME_DTYPE  : 'mType2',
            NAME_SHAPE  : (TEST_NUM_M , TEST_NUM_N)
            #            NAME_CENTER : 2,
        }),
        'arr3': ArrayGenerator({
            NAME_DTYPE  : 'mType1',
            NAME_SHAPE  : (TEST_NUM_N , TEST_NUM_M)
            #            NAME_CENTER : 2,
        }),
        'num4': ArrayGenerator({
            NAME_DTYPE  : 'sType',
            NAME_SHAPE  : (1,)
            #            NAME_CENTER : 2,
        }),
        TEST_OBJECT: Product,
        TEST_INITARGS: (lambda param : [
            param['num4']()[0],
            Matrix(param['arr1']()),
            Matrix(param['arr2']()),
            Matrix(param['arr3']())
        ]),
        'strType': (lambda param: NAME_TYPES[param['sType']]),
        TEST_NAMINGARGS: dynFormatString(
            "%s*%s*%s*%s", 'strType', 'arr1', 'arr2', 'arr3'),
        TEST_TOL_POWER: 3.
    },
    TEST_CLASS: {
        # test basic class methods
    }, TEST_TRANSFORMS: {
    }
}


################################################## Benchmarks
from .Fourier import Fourier
from .Hadamard import Hadamard
from .Eye import Eye

benchmark = {
    NAME_COMMON: {
        NAME_DOCU       : r'''$\bm P = \bm \Hs_k \cdot \bm \Fs_{2^k}$;
            so $n = 2^k$''',
        BENCH_FUNC_GEN  : (lambda c: Product(Hadamard(c), Fourier(2 ** c))),
        BENCH_FUNC_SIZE : (lambda c: 2 ** c),
        BENCH_FUNC_STEP : (lambda c : c + 1)
    },
    BENCH_FORWARD: {
    },
    BENCH_SOLVE: {
    },
    BENCH_OVERHEAD: {
        BENCH_FUNC_GEN  : (lambda c : Product(*([Eye(2 ** c)] * 1000))),
        NAME_DOCU       : r'''Produkt of $1000$ Identity matrices
            $\bm I_{2^k}$; so $n = 2^k$'''
    }
}


################################################## Documentation
docLaTeX = r"""

\subsection{Product (\texttt{fastmat.Product})}
\subsubsection{Definition and Interface}
\[\bm M = \prod\limits_i \bm A_i \]
where the $A_{i}$ can be fast transforms of \emph{any} type.

\begin{snippet}
\begin{lstlisting}[language=Python]
# import the package
import fastmat as fm

# define the product terms
A = fm.Circulant(x_A)
B = fm.Circulant(x_B)

# construct the product
M = fm.Product(A.H, B)
\end{lstlisting}

Assume we have two circulant matrices $\bm A$ and $\bm B$. Then we define
\[\bm M = \bm A_c^\herm \bm B_c.\]
\end{snippet}
"""
