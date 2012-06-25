(load "./tests-driver.scm")
(load "./tests-1.1-req.scm")

(define (emit-program x)
  (unless (integer? x) (error ---))
  (emit "    .text")
#|
  (emit "    .global _scheme_entry")
  (emit "    .def	_scheme_entry;	.scl	2;	.type	32;	.endef")
  (emit "_scheme_entry:")
|#
  (emit ".globl scheme_entry")
  (emit "    .type	scheme_entry, @function")
  (emit "scheme_entry:")

  (emit "    movl $~s, %eax" x)
  (emit "    ret"))

;;;;

(define (main args)
  (test-all "1.1.runtime.c")
  0)
