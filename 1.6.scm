(load "./tests-driver.scm")
(load "./tests-1.6-req.scm")
(load "./tests-1.5-req.scm")
(load "./tests-1.4-req.scm")
(load "./tests-1.3-req.scm")
(load "./tests-1.2-req.scm")
(load "./tests-1.1-req.scm")

(define fxshift 2)
(define fxmask #x03)
(define fxtag #x00)
(define bool_f #x2f)
(define bool_t #x6f)
(define bool_bit 6)
(define bool_mask #xbf)
(define bool_tag  #x2f)
(define wordsize 4) ; bytes

(define nullval #b00111111)
(define charshift 8)
(define chartag #b00001111)
(define charmask #xff)

(define fixnum-bits (- (* wordsize 8) fxshift))

(define fxlower (- (expt 2 (- fixnum-bits 1))))

(define fxupper (sub1 (expt 2 (- fixnum-bits 1))))


(define (emit-program expr)
  (emit-function-header "scheme_entry")
  (emit "    movl %esp, %ecx")
  (emit "    movl 4(%esp), %esp")
  (emit "    call L_scheme_entry")
  (emit "    movl %ecx, %esp")
  (emit "    ret")
  
  (emit-label "L_scheme_entry")
  (emit-expr (- wordsize) '() expr)
  (emit "    ret"))

(define (emit-function-header funcname)
  (emit "    .text")
  (emit (string-append "    .global " funcname))
;  (emit (string-append "    .def	" funcname ";	.scl	2;	.type	32;	.endef"))
  (emit (string-append "    .type " funcname ", @function"))

  (emit (string-append funcname ":")))

(define (emit-expr si env expr)
  (cond
   ((immediate? expr) (emit-immediate expr))
   ((variable? expr)  (emit-variable-ref env expr))
   ((if? expr)        (emit-if si env expr))
   ((and? expr)       (emit-and si env expr))
   ((or? expr)        (emit-or si env expr))
   ((let? expr)       (emit-let si env expr))
   ((primcall? expr)  (emit-primcall si env expr))
   ((predicate-call? expr) (emit-predicate-val si env expr))
   (else (error "not implemented"))))

(define (emit-immediate x)
  (emit "    movl $~s, %eax" (immediate-rep x)))

(define (emit-primcall si env expr)
  (let ((prim (car expr))
		(args (cdr expr)))
    (check-primcall-args prim args)
    (apply (primitive-emitter prim) si env args)))

(define (emit-predicate-val si env expr)
  (let ((c (emit-predicate-test si env expr))
		(prim (car expr))
		(args (cdr expr)))
    (emit-to-boolean c)))

(define (emit-predicate-test si env expr)
  (let ((prim (car expr))
		(args (cdr expr)))
    (check-primcall-args prim args)
    (apply (predicate-emitter prim) si env args)))

(define (emit-label label)
  (emit "~a:" label))

(define (emit-test si env expr)
  (if (predicate-call? expr)
	  (emit-predicate-test si env expr)
    (begin
      (emit-expr si env expr)
      (emit "    cmp $~s, %al" bool_f)
      'NEQ)))

(define (emit-jump-if-not pred label)
  (let ((c (case pred
			 ((EQ)  "jne")
			 ((NEQ) "je")
			 ((LT)  "jge")
			 ((GT)  "jle")
			 ((LE)  "jg")
			 ((GE)  "Jl")
			 (else (error "illegal condition")))))
	(emit "    ~a ~a" c label)))

(define (emit-if si env expr)
  (let ((alt-label (unique-label))
        (end-label (unique-label)))
    (emit-jump-if-not (emit-test si env (if-test expr))
					  alt-label)
    (emit-expr si env (if-conseq expr))
    (emit "    jmp ~a" end-label)
    (emit-label alt-label)
    (emit-expr si env (if-altern expr))
    (emit-label end-label)))

(define (emit-and si env expr)
  (define (test-false expr false-label end-label)
    (if (predicate-call? expr)
        (begin
          (emit-predicate-test si env expr)
          (emit "    jne ~a" false-label))  ; 判定が失敗したら #f の代入に飛ぶ
      (begin
        (emit-test si env expr)
        (emit "    je ~a" end-label))))  ; 値の場合はすでに #f になっているので直接終了へ飛ぶ
  (let ((p (cdr expr)))
    (cond ((null? p)
           (emit "    mov $~s, %eax" bool_t))
          (else
           (let ((false-label (unique-label))
                 (end-label (unique-label)))
             (let loop ((p p))
               (if (null? (cdr p)) ; 最後
                   (emit-expr si env (car p))
                 (begin
                   (test-false (car p) false-label end-label)
                   (loop (cdr p)))))
             (emit "    jmp ~a" end-label)
             (emit-label false-label)
             (emit "    mov $~s, %eax" bool_f)
             (emit-label end-label))))))

(define (emit-or si env expr)
  (define (test-true expr true-label end-label)
    (if (predicate-call? expr)
        (begin
          (emit-predicate-test si env expr)
          (emit "    je ~a" true-label))  ; 判定が成功したら #t の代入に飛ぶ
      (begin
        (emit-test si env expr)
        (emit "    jne ~a" end-label))))  ; 値の場合は真だったら終了に飛ぶ
  (let ((p (cdr expr)))
    (cond ((null? p)
           (emit "    mov $~s, %eax" bool_f))
          (else
           (let ((true-label (unique-label))
                 (end-label (unique-label)))
             (let loop ((p p))
               (if (null? (cdr p))
                   (emit-expr si env (car p))
                 (begin
                   (test-true (car p) true-label end-label)
                   (loop (cdr p)))))
             (emit "    jmp ~a" end-label)
             (emit-label true-label)
             (emit "    mov $~s, %eax" bool_t)
             (emit-label end-label))))))

(define (emit-let si env expr)
  (define (process-let bindings si new-env)
	(cond
	 ((empty? bindings)
	  (emit-expr si new-env (let-body expr)))
	 (else
	  (let ((b (first bindings)))
		(emit-expr si env (rhs b))
		(emit-stack-save si)
		(process-let (rest bindings)
					 (next-stack-index si)
					 (extend-env (lhs b) si new-env))))))
  (process-let (let-bindings expr) si env))

(define (emit-stack-save si)
  (emit "    movl %eax, ~s(%esp)" si))

(define (emit-stack-load si)
  (emit "    movl ~s(%esp), %eax" si))

(define (emit-variable-ref env var)
  (cond
   ((lookup var env) => emit-stack-load)
   (else (error "unbound variable: " var))))

(define (emit-to-boolean c)
  (let ((op (case c
			  ((EQ)  "sete")
			  ((NEQ) "setne")
			  ((LT)  "setl")
			  ((GT)  "setg")
			  ((LE)  "setle")
			  ((GE)  "setge")
			  (else (error "illegal condition")))))
	(emit "    ~a %al" op)
	(emit "    movzbl %al, %eax")
	(emit "    sal $~s, %al" bool_bit)
	(emit "    or $~s, %al" bool_f)))



(define (fixnum? x)
  (and (integer? x) (exact? x) (<= fxlower x fxupper)))

(define (immediate? x)
  (or (fixnum? x) (boolean? x) (char? x) (null? x)))

(define (immediate-rep x)
  (cond
   ((fixnum? x) (ash x fxshift))
   ((eq? x #t) bool_t)
   ((eq? x #f) bool_f)
   ((char? x) (+ (ash (char->integer x) charshift) chartag))
   ((null? x) nullval)
   (else (error "must not happen"))))


(define-syntax define-primitive
  (syntax-rules ()
    ((_ (prim-name si env arg* ...) b b* ...)
     (begin
       (putprop 'prim-name '*is-prim* #t)
       (putprop 'prim-name '*arg-count*
                (length '(arg* ...)))
       (putprop 'prim-name '*emitter*
                (lambda (si env arg* ...) b b* ...))))))

(define (primitive? x)
  (and (symbol? x) (getprop x '*is-prim*)))

(define (primitive-emitter x)
  (or (getprop x '*emitter*) (error "must not happen")))

(define (primcall? expr)
  (and (pair? expr) (primitive? (car expr))))

(define (check-primcall-args prim args)
  (let ((n (getprop prim '*arg-count*))
        (m (length args)))
    (if (= m n)
        #t
      (error "illegal argnum:" m 'for n))))


(define-syntax define-predicate
  (syntax-rules ()
    ((_ (prim-name si env arg* ...) b b* ...)
     (begin
       (putprop 'prim-name '*is-predicate* #t)
       (putprop 'prim-name '*arg-count*
                (length '(arg* ...)))
       (putprop 'prim-name '*emitter*
                (lambda (si env arg* ...) b b* ...))))))

(define (predicate? x)
  (and (symbol? x) (getprop x '*is-predicate*)))

(define (predicate-call? expr)
  (and (pair? expr) (predicate? (car expr))))

(define (predicate-emitter x)
  (or (getprop x '*emitter*) (error "must not happen")))



(define unique-label
  (let ((count 0))
    (lambda ()
      (let ((L (format "L_~s" count)))
        (set! count (add1 count))
        L))))

(define (if? expr)
  (and (pair? expr) (eq? (car expr) 'if)))

(define (if-test expr) (cadr expr))
(define (if-conseq expr) (caddr expr))
(define (if-altern expr) (cadddr expr))

(define (and? expr)
  (and (pair? expr) (eq? (car expr) 'and)))

(define (or? expr)
  (and (pair? expr) (eq? (car expr) 'or)))


(define (let? expr)
  (and (pair? expr) (eq? (car expr) 'let)))

(define (let-bindings expr)
  (cadr expr))

(define (let-body expr)
  (caddr expr))

(define empty? null?)
(define first car)
(define rest cdr)
(define lhs car)
(define rhs cadr)
(define (next-stack-index si) (- si wordsize))
(define (variable? x)
  (symbol? x))

(define (extend-env varname si env)
  (cons (cons varname si) env))

(define (lookup var env)
  (let ((a (assoc var env)))
	(if a
		(cdr a)
		#f)))




(define-primitive ($fxadd1 si env arg)
  (emit-expr si env arg)
  (emit "    addl $~s, %eax" (immediate-rep 1)))

(define-primitive ($fxsub1 si env arg)
  (emit-expr si env arg)
  (emit "    subl $~s, %eax" (immediate-rep 1)))

(define-primitive ($fixnum->char si env arg)
  (emit-expr si env arg)
  (emit "    shll $~s, %eax" (- charshift fxshift))
  (emit "    orl $~s, %eax" chartag))

(define-primitive ($char->fixnum si env arg)
  (emit-expr si env arg)
  (emit "    shrl $~s, %eax" (- charshift fxshift)))

(define-predicate (fixnum? si env arg)
  (emit-expr si env arg)
  (emit "    and $~s, %al" fxmask)
  (emit "    cmp $~s, %al" fxtag)
  'EQ)

(define-predicate ($fxzero? si env arg)
  (emit-expr si env arg)
  (emit "    testl %eax, %eax")
  'EQ)

(define-predicate (null? si env arg)
  (emit-expr si env arg)
  (emit "    cmp $~s, %al" nullval)
  'EQ)

(define-predicate (boolean? si env arg)
  (emit-expr si env arg)
  (emit "    and $~s, %al" bool_mask)
  (emit "    cmp $~s, %al" bool_tag)
  'EQ)

(define-predicate (char? si env arg)
  (emit-expr si env arg)
  (emit "    and $~s, %al" charmask)
  (emit "    cmp $~s, %al" chartag)
  'EQ)

(define-predicate (not si env arg)
  (emit-expr si env arg)
  (emit "    cmp $~s, %al" bool_f)
  'EQ)

(define-primitive (fxlognot si env arg)
  (emit-expr si env arg)
  (emit "    notl %eax")
  (emit "    and $~s, %eax" (lognot fxmask)))


(define-primitive (fx+ si env arg1 arg2)
  (define (out2)
	(emit-expr si env arg1)
	(emit "    movl %eax, ~s(%esp)" si)
	(emit-expr (- si wordsize) env arg2)
	(emit "    addl ~s(%esp), %eax" si))
  (define (out1 expr const)
	(emit-expr si env expr)
	(emit "    addl $~s, %eax" (immediate-rep const)))
  ;; ２つとも定数の場合はもっと上位で畳み込んでいる予定なので、ここでは処理しない
  (cond ((fixnum? arg2) (out1 arg1 arg2))
		((fixnum? arg1) (out1 arg2 arg1))
		(else (out2))))

(define-primitive (fx- si env arg1 arg2)
  (define (out2)
	(emit-expr si env arg2)
	(emit "    movl %eax, ~s(%esp)" si)
	(emit-expr (- si wordsize) env arg1)
	(emit "    subl ~s(%esp), %eax" si))
  (define (out1 expr const)
	(emit-expr si env expr)
	(emit "    subl $~s, %eax" (immediate-rep const)))
  (cond ((fixnum? arg2) (out1 arg1 arg2))
		(else (out2))))

(define-primitive (fx* si env arg1 arg2)
  (define (out2)
	(emit-expr si env arg1)
	(emit "    sarl $2, %eax")  ; 右シフト
	(emit "    movl %eax, ~s(%esp)" si)
	(emit-expr (- si wordsize) env arg2)
	(emit "    imull ~s(%esp), %eax" si))
  (define (out1 expr const)
	(emit-expr si env expr)
	(emit "    imull $~s, %eax" const))  ; シフト必要なし
  (cond ((fixnum? arg2) (out1 arg1 arg2))
		((fixnum? arg1) (out1 arg2 arg1))
		(else (out2))))

(define-primitive (fxlogor si env arg1 arg2)
  (emit-expr si env arg1)
  (emit "    movl %eax, ~s(%esp)" si)
  (emit-expr (- si wordsize) env arg2)
  (emit "    orl ~s(%esp), %eax" si))

(define-primitive (fxlogand si env arg1 arg2)
  (emit-expr si env arg1)
  (emit "    movl %eax, ~s(%esp)" si)
  (emit-expr (- si wordsize) env arg2)
  (emit "    andl ~s(%esp), %eax" si))

(define-predicate (fx= si env arg1 arg2)
  (emit-expr si env arg1)
  (emit "    movl %eax, ~s(%esp)" si)
  (emit-expr (- si wordsize) env arg2)
  (emit "    cmpl ~s(%esp), %eax" si)
  'EQ)

(define-predicate (fx< si env arg1 arg2)
  (emit-expr si env arg2)
  (emit "    movl %eax, ~s(%esp)" si)
  (emit-expr (- si wordsize) env arg1)
  (emit "    cmpl ~s(%esp), %eax" si)
  'LT)

(define-predicate (fx<= si env arg1 arg2)
  (emit-expr si env arg2)
  (emit "    movl %eax, ~s(%esp)" si)
  (emit-expr (- si wordsize) env arg1)
  (emit "    cmpl ~s(%esp), %eax" si)
  'LE)

(define-predicate (fx> si env arg1 arg2)
  (emit-expr si env arg2)
  (emit "    movl %eax, ~s(%esp)" si)
  (emit-expr (- si wordsize) env arg1)
  (emit "    cmpl ~s(%esp), %eax" si)
  'GT)

(define-predicate (fx>= si env arg1 arg2)
  (emit-expr si env arg2)
  (emit "    movl %eax, ~s(%esp)" si)
  (emit-expr (- si wordsize) env arg1)
  (emit "    cmpl ~s(%esp), %eax" si)
  'GE)

;;;;

(define (main args)
  (test-all "1.5.runtime.c")
  0)
