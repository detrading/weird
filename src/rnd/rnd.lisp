(in-package :rnd)

(deftype pos-single () `(single-float 0f0 *))


(defun set-rnd-state (i)
  (declare (fixnum i))
   #+SBCL ; this is called feature expressions
   (setf *random-state* (sb-ext:seed-random-state i))

   #+(not SBCL)
   (warn "rnd:state is only implemented for SBCL. see src/rnd.lisp
          to implement state for your environment."))

(defun make-rnd-state () (setf *random-state* (make-random-state t)))


; NUMBERS AND RANGES

(declaim (inline rndi))
(defun rndi (a)
  (declare #.*opt* (fixnum a))
  (the fixnum (random a)))

(declaim (inline nrndi))
(defun nrndi (n a)
  (declare #.*opt* (weird:pos-int n a))
  (loop repeat n collect (rndi a) of-type fixnum))


(declaim (inline rndrngi))
(defun rndrngi (a b)
  (declare #.*opt* (fixnum a b))
  (+ a (rndi (- b a))))

(declaim (inline nrndrngi))
(defun nrndrngi (n a b)
  (declare #.*opt* (weird:pos-int n) (fixnum a b))
  (let ((d (- b a)))
    (declare (fixnum d))
    (loop repeat n collect (+ a (rndi d)) of-type fixnum)))


(declaim (inline rnd))
(defun rnd (&optional (x 1f0))
  (declare #.*opt* (veq:ff x))
  (random x))

(declaim (inline nrnd))
(defun nrnd (n &optional (x 1f0))
  (declare #.*opt* (weird:pos-int n) (veq:ff x))
  (loop repeat n collect (rnd x) of-type veq:ff))


(declaim (inline rnd*))
(defun rnd* (&optional (x 1f0))
  (declare #.*opt* (veq:ff x))
  (- x (rnd (* 2f0 x))))

(declaim (inline nrnd*))
(defun nrnd* (n &optional (x 1f0))
  (declare #.*opt* (weird:pos-int n) (veq:ff x))
  (loop repeat n collect (rnd* x) of-type veq:ff))


(declaim (inline rndrng))
(defun rndrng (a b)
  (declare #.*opt* (veq:ff a b))
  (+ a (rnd (- b a))))

(declaim (inline nrndrng))
(defun nrndrng (n a b)
  (declare #.*opt* (weird:pos-int n) (veq:ff a b))
  (loop repeat n collect (rndrng a b) of-type veq:ff))


; https://en.wikipedia.org/wiki/Box%E2%80%93Muller_transform
(defun norm (&key (mu 0f0) (sigma 1f0))
  (declare #.*opt* (veq:ff mu sigma))
  "box-muller transform"
  (let ((s (* sigma (the veq:ff
                         (sqrt (the pos-single
                                    (* -2f0 (log (rnd))))))))
        (u (rnd veq:fpii)))
    (declare (veq:ff s u))
    (values (+ mu (* s (cos u)))
            (+ mu (* s (sin u))))))


; MACROS

(defmacro prob (p a &optional b)
  "executes body with probability p"
  `(if (< (rnd) (the veq:ff ,p)) ,a ,b))

(defmacro either (a &optional b)
  "excecutes either a or b, with a probablility of 0.5"
  `(prob 0.5f0 ,a ,b))


; TODO: sum to 1?
(defmacro rcond (&rest clauses)
  "
  executes the forms in clauses according to the weighted sum of
  all p1, p2 ...
  clauses should be on this form:
    ((p1 form) (p2 form) ...)
  "
  (weird:awg (val)
    (let* ((tot 0f0)
           (clauses (loop for (p . body) in clauses
                          do (incf tot (veq:ff p))
                          collect `((< ,val ,tot) ,@body))))
      (declare (veq:ff tot) (list clauses))
      `(let ((,val (rnd ,tot)))
         (declare (veq:ff ,val))
         (cond ,@clauses)))))


(defmacro rep (a &optional b &body body)
  "repeat body at most a times, or between a and b times"
  `(loop repeat ,(if (and a b) `(rndrngi ,a ,b) `(rndi ,a))
         do (progn ,@body)))

; GENERIC

(defun rndget (l)
  (declare #.*opt* (sequence l))
  (typecase l (cons (nth (rndi (length (the list l))) l))
              (vector (aref l (rndi (length l))))
              (t (error "incorrect type in rndget: ~a" l))))


(defun rndspace (n a b &key order &aux (d (- b a)))
  (declare #.*opt* (weird:pos-int n) (veq:ff a b d))
  (if order (sort (loop repeat n collect (+ a (rnd d)) of-type veq:ff) #'<)
            (loop repeat n collect (+ a (rnd d)) of-type veq:ff)))


(defun rndspacei (n a b &key order &aux (d (- b a)))
  (declare #.*opt* (weird:pos-int n) (fixnum a b d))
  (if order (sort (loop repeat n collect (+ a (rndi d)) of-type fixnum) #'<)
            (loop repeat n collect (+ a (rndi d)) of-type fixnum)))


(defun bernoulli (n p)
  (declare #.*opt* (weird:pos-int n) (veq:ff p))
  (loop repeat n collect (prob p 1f0 0f0) of-type veq:ff))


; https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle
(defun shuffle (a* &aux (n (length a*)))
  (declare #.*opt* (weird:pos-int n) (simple-array a*))
  "shuffle a with fisher yates algorithm"
  (loop for i of-type weird:pos-int from 0 to (- n 2)
        do (rotatef (aref a* i) (aref a* (rndrngi i n))))
  a*)


(defun nrnd-from (n a)
  (declare #.*opt* (weird:pos-int n) (vector a))
  "n random elements from a."
  (loop for i in (nrndi n (length a)) collect (aref a i)))

(defun nrnd-from* (n a)
  (declare #.*opt* (weird:pos-int n) (vector a))
  "n random distinct elements from a. assumes no dupes in a"
  (let* ((a* (ensure-vector a))
         (resind nil)
         (anum (length (the simple-array a*))))
    (when (> n anum) (error "not enough distinct elements in a."))
    (loop until (>= (hset:num (hset:make :init resind)) n)
          do (setf resind (nrndi n anum)))
    (loop for i in resind collect (aref a* i))))


; TODO: port this
; some version of mitchell's best candidate algorithm
; https://bl.ocks.org/mbostock/1893974/c5a39633db9c8b1f12c73b069e002c388d4cb9bf
; TODO: make n the max number instead of the new sample number
; (defun max-distance-sample (n fx &key (sample-num 50) (dstfx #'vec:dst2)
;                                       (res (weir-utils:make-adjustable-vector)))
;   (declare (fixnum n sample-num) (function fx dstfx) (array res))
;   "
;   randomly sample a total of n items using (funcall fx sample-num), selecting
;   the element furthest from existing elemets.
;   example:

;     (rnd:max-distance-sample 100
;       (lambda (g) (rnd:nin-circ g 400f0)))
;   "
;   (labels ((-get-cand (c) (second (first c)))
;            (-closest (res* c) (loop for v across res*
;                                     minimizing (funcall dstfx v c))))
;     (loop with wanted-length of-type fixnum = (+ n (length res))
;           until (>= (length res) wanted-length)
;           do (weir-utils:vextend
;                (-get-cand (sort (loop for c in (funcall fx sample-num)
;                                       collect (list (-closest res c) c))
;                           #'> :key #'first))
;                res))
;     res))

