;;; File: dodgeball.lisp -*- Mode: Lisp; Syntax: Common-Lisp; -*-
;;;; The Dodgeball World Environment


;;;================================================================
;;; The world definition


(defconstant single-mode 1)
(defconstant competetive-mode 2)

(defstructure (db-world 
               (:include grid-environment
                         (size (@ 10 10))                ; 20 x 20 grid environment
                         (aspec nil)                     ; dodging agents
                         (bspec '((at edge wall)         ; grid edges are wall
                                  ball))                 ; 1 ball at a random location
                         ))
    "the dodgeball world"
  (game-mode single-mode)
  (agents-at-ball nil) ; (cons (the agent that is standing where the ball is) (no of turns he stands there)) : 
  ;; used for keeping record of agents who hold the ball excessively
  (agents-holding nil)
  (agents-lives nil); ; alist of agents and their lives
  (agents-hits nil) ; alist of agents and hits they made
  (agents-outlived nil) ; alist of agents and number of other agents they survived
  )          ; cons holding (car) an agent that holds the ball and number of turns he held it (cdr)

(defmethod agent-lives ((env db-world) (ag agent-body))
  (cdr (assoc ag (db-world-agents-lives env))))

(defmethod agent-hits ((env db-world) (ag agent-body))
  (cdr (assoc ag (db-world-agents-hits env))))

(defmethod agent-outlived ((env db-world) (ag agent-body))
  (cdr (assoc ag (db-world-agents-outlived env))))

(defmethod agent-has-ball ((env db-world) (ag agent-body))
  (cdr (assoc ag (db-world-agents-holding env))))

(defmethod agent-turns-with-ball ((env db-world) (ag agent-body))
  "returns a number of turns the agent is holding the ball or nil if he is not holding the ball."
  (cdr (assoc ag (db-world-agents-at-ball env))))

(defmethod agent-lost-life ((env db-world) (ag agent-body))
  ;;(format t "~A lost life and now has ~A lives~%" ag (- (agent-lives env ag) 1))
  (setf (cdr (assoc ag (db-world-agents-lives env))) (- (agent-lives env ag) 1))
  (when (not (agent-alive env ag))
    (remove-agent env ag)))

(defmethod remove-agent ((env db-world) (ag agent-body))
  ;;(format t "~A is removed from the env.~%" ag)
  ; release the ball if he has it
  (when (agent-has-ball env ag)
    (throw-ball env ag (car (object-loc ag)) (cadr (object-loc ag))))
  (setf (cdr (assoc ag (db-world-agents-at-ball env))) nil)
  (setf (cdr (assoc ag (db-world-agents-holding env))) nil)
  (remove-object ag env)
  (dolist (ag-alive (db-world-agents-outlived env))
      (when (agent-alive env (car ag-alive)) (agent-outlived-another env (car ag-alive)))))

(defmethod agent-alive ((env db-world) (ag agent-body))
  (> (agent-lives env ag) 0))

(defmethod agent-scored-hit ((env db-world) (ag agent-body))
  ;;(format t "~A scored a hit and now has ~A hits.~%" ag (+ 1 (agent-hits env ag)))
  (setf (cdr (assoc ag (db-world-agents-hits env))) (+ 1 (agent-hits env ag))))

(defmethod agent-outlived-another ((env db-world) (ag agent-body))
  ;;(format  t "~A outlived another.~%" ag)
  (setf (cdr (assoc ag (db-world-agents-outlived env))) (+ 1 (agent-outlived env ag))))

(defmethod agent-threw-ball ((env db-world) (ag agent-body))
  ;;(format t "~A threw ball~%" ag)
  (setf (cdr (assoc ag (db-world-agents-holding env))) nil)
  (let* ((loc (object-loc ag)) 
         (ball (ball-at-p env loc)))
    (when (not ball) ; when not standing where the ball is, then perform next line:
      (setf (cdr (assoc ag (db-world-agents-at-ball env))) nil))))

(defmethod agent-got-ball ((env db-world) (ag agent-body))
  ;;(format t "~A got ball~%" ag)
  (setf (cdr (assoc ag (db-world-agents-holding env))) t)
  (when (not (agent-turns-with-ball env ag))
    (setf (cdr (assoc ag (db-world-agents-at-ball env))) 0)))

(defmethod agent-at-ball ((env db-world) (ag agent-body))
  ;;(format t "~a is standing where the ball is.~%" ag)
  (let ((tmp (assoc ag (db-world-agents-at-ball env))))
    (when (null (cdr tmp))
      (setf (cdr tmp) 0))))

(defmethod agent-not-at-ball ((env db-world) (ag agent-body))
  ;;(format t "~a is NOT standing where the ball is.~%" ag)
  (let ((tmp (assoc ag (db-world-agents-at-ball env))))
    (when (cdr tmp)
      (setf (cdr tmp) nil))))

(defmethod increase-time-with-ball ((env db-world))
  (dolist (agent-time (db-world-agents-at-ball env))
    (when (cdr agent-time)
      (incf (cdr agent-time))
      ;;(format t "~A is standing at the ball for one more time, ~A in total~%" (car agent-time) (cdr agent-time) )
      (when (> (cdr agent-time) 3)
        (agent-lost-life env (car agent-time))))))


;;; ==========================================================
;;; percept objects definition


(defstructure (percept-object)
    "objects that are percieved by the agent in the environment"
  (name ""))

(defstructure (percept-object-wall (:include percept-object)))

(defstructure (percept-object-ball (:include percept-object)))

(defstructure (percept-object-agent (:include percept-object))
  (lives 0)
  (has-ball nil))


;;; ==================================================================
;;;; percept redefinition


(defun get-percept-grid (env)
  (transform-percept (my-copy-array (db-world-grid env)) env))

(defmethod get-percept ((env db-world) agent)
  (let ((ag-body (agent-body agent)))
    (list ag-body (get-percept-grid env))))

(defun transform-percept (grid env)
    (dotimes (x (car (array-dimensions grid)))
      (dotimes (y (cadr (array-dimensions grid)))
        (let ((tmp nil)(elems (aref grid x y)))
          (dolist (elem elems)
            (cond ((typep elem 'agent-body) 
                   (push (make-percept-object-agent :name (object-name elem) :lives (agent-lives env elem) :has-ball (agent-has-ball env elem)) tmp))
                  ((typep elem 'obstacle) 
                   (push (make-percept-object-wall :name (object-name elem)) tmp))
                  ((typep elem 'ball) 
                   (push (make-percept-object-ball :name (object-name elem)) tmp))
                  (t (print "unknown element in grid"))))
          (setf (aref grid x y) tmp)))) grid )


;;; ==========================================================
;;; agent definition


(defstructure (db-agent 
                (:include agent (body (make-db-agent-body))))
    "An agent for db world."
  )

(defstructure (db-agent-body (:include agent-body)) ; it is an object holding nil
    (grid nil))


;;; ==========================================================
;;; interactive agent definition


(defstructure (ask-user-db-agent (:include db-agent (program 'ask-user-db))) 
    "An agent that asks the user to type in an action.")

(defun parse-line (string)
  (if (or (null string) (equal "" string)) nil
    (let ((read (multiple-value-list (read-from-string string))))
      (if (car read) (cons (car read) (parse-line (subseq string (cadr read)))) nil ))))

(defun ask-user-db (percept)
  "Ask the user what action to take."
  (format t 
     "~&action (go-right go-up go-left go-down grab-ball throw-ball stop stay)? ")
  (parse-line (read-line)))


;;; ==========================================================
;;; evil, back-throwing agent definition


(defconstant wait-and-throw-db-agent-name "WT")

(defstructure (wait-and-throw-db-agent-body (:include db-agent-body (name wait-and-throw-db-agent-name))))

(defstructure (wait-and-throw-db-agent                
               (:include db-agent 
                         (program 'wait-and-throw-at-student) 
                         (body (make-wait-and-throw-db-agent-body))
                         (name wait-and-throw-db-agent-name)))
    "An agent that will be attempting to hit the student in the first part of the semestral project.")

(defun wait-and-throw-at-student (percept)
  "Wait one turn and then throw the ball at the student"
  (let* ((me (car percept))
         (grid (cadr percept))
         (ball-on-my-loc (member-if (lambda (a) (typep a 'percept-object-ball)) (apply #'aref grid (object-loc me))))
         (holding-ball (object-contents me))
         (student-loc (find-student-location grid)))
    (when (not student-loc)
      (return-from wait-and-throw-at-student 'stop))
    (when ball-on-my-loc 
      (return-from wait-and-throw-at-student 'grab-ball))
    (when holding-ball
      ;(print holding-ball)
      ;(format t "~& the ball is mine ~%")
      ;;(format t "Will throw the ball: ~a~%" `(throw-ball ,@student-loc))
      (return-from wait-and-throw-at-student `(throw-ball ,@student-loc)))
    'stay))

(defun find-student (grid)
  (let (student)
    (dotimes (numberx (car (array-dimensions grid)))
      (dotimes (numbery (cadr (array-dimensions grid)))
        (when (setf student (identify-in-list #'student-p (aref grid numberx numbery)))
          (return-from find-student student))))) nil )

(defun find-student-location (grid)
  (dotimes (numberx (car (array-dimensions grid)))
    (dotimes (numbery (cadr (array-dimensions grid)))
      (when (identify-in-list #'student-p (aref grid numberx numbery))
        (return-from find-student-location (list numberx numbery))))) nil )

(defun identify-in-list (pred list)
  (dolist (item list)
    (when (funcall pred item)
      (return-from identify-in-list item))) nil)

(defmethod student-p ((obj percept-object))
  (if (and (not (equal (percept-object-name obj) "#")) 
           (not (equal (percept-object-name obj) wait-and-throw-db-agent-name)) 
           (not (equal (percept-object-name obj) "B")))
      obj nil))


;;; ================================================================
;;; Student's agent definition:


(defconstant janecjak-agent-name "JJ")
(defparameter *janecjak-strategy* 1)
(defparameter *janecjak-strategy-symbol1* 'stay)
(defparameter *janecjak-strategy-symbol2* 'stay)
(defparameter *janecjak-step-count* 0)

(defstructure
    (janecjak
        (:include db-agent
            (body (make-janecjak-agent-body))
            (program 'janecjak-agent-program)
            (name janecjak-agent-name)
        )
    )
)

(defstructure
	(janecjak-agent-body
        (:include db-agent-body (name janecjak-agent-name))
	)
)

(defun janecjak-agent-program (percept)
	(let*
        ((me (car percept))
         (grid (cadr percept))
         (my-location (janecjak-my-location grid))
         (ball-on-my-location (member-if (lambda (a) (percept-object-ball-p a)) (apply #'aref grid (object-loc me))))
         (holding-ball (object-contents me))
         (ball-location (janecjak-ball-location grid))
         (opponent-locations (janecjak-opponent-locations grid))
        )
        (when (not opponent-locations)
            (return-from janecjak-agent-program 'stop)
        )
        (when ball-on-my-location
            (return-from janecjak-agent-program 'grab-ball)
        )
        (when holding-ball
            (return-from janecjak-agent-program `(throw-ball ,@(janecjak-nearest-opponent my-location opponent-locations)))
        )
        
        (cond
            ((equal *janecjak-strategy* 2)
            (cond
                ((equal *janecjak-step-count* 0)
                    (progn
                        (setf *janecjak-step-count* (+ 1 *janecjak-step-count*))
                        (return-from janecjak-agent-program *janecjak-strategy-symbol1*)
                    )
                )
                ((< *janecjak-step-count* 3)
                    (progn
                        (setf *janecjak-step-count* (+ 1 *janecjak-step-count*))
                        (return-from janecjak-agent-program *janecjak-strategy-symbol2*)
                    )
                )
                ((equal *janecjak-step-count* 3)
                    (let ((symb *janecjak-strategy-symbol2*))
                        (progn
                            (setf *janecjak-strategy* (nth (random 2) '(1 3)))
                            (setf *janecjak-step-count* 0)
                            (setf *janecjak-strategy-symbol1* 'stay)
                            (setf *janecjak-strategy-symbol2* 'stay)
                            (return-from janecjak-agent-program symb)
                        )
                    )
                )
            )
            )
            ((equal *janecjak-strategy* 1)
            (cond
            	((null ball-location) (janecjak-escape my-location grid))
            	((and
                     (janecjak-test-next-field grid (car my-location) (+ (cadr my-location) 1))
                     (< (cadr my-location) (cadr ball-location))
                 )
                     'go-up
                )
                ((and
                     (janecjak-test-next-field grid (+ (car my-location) 1) (cadr my-location))
                     (< (car my-location) (car ball-location))
                 )
                     'go-right
                )
                ((and
                     (janecjak-test-next-field grid (car my-location) (- (cadr my-location) 1))
                     (> (cadr my-location) (cadr ball-location))
                 )
                     'go-down
                )
                ((and
                     (janecjak-test-next-field grid (- (car my-location) 1) (cadr my-location))
                     (> (car my-location) (car ball-location))
                 )
                     'go-left
                )
                ((< (cadr my-location) (cadr ball-location))
                    (if (janecjak-test-next-field grid (car my-location) (+ (cadr my-location) 1))
                        'go-up
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-left go-right go-down))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-up)
                                (if (equal symb 'go-down)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-left go-right)))
                                )
                            )
                            'stay
                        )
                    )
                )
                ((< (car my-location) (car ball-location))
                    (if (janecjak-test-next-field grid (+ (car my-location) 1) (cadr my-location))
                        'go-right
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-up go-down go-left))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-right)
                                (if (equal symb 'go-left)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-up go-down)))
                                )
                            )
                            'stay
                        )
                    )
                )
                ((> (cadr my-location) (cadr ball-location))
                    (if (janecjak-test-next-field grid (car my-location) (- (cadr my-location) 1))
                        'go-down
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-left go-right go-up))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-down)
                                (if (equal symb 'go-up)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-left go-right)))
                                )
                            )
                            'stay
                        )
                    )
                )
                ((> (car my-location) (car ball-location))
                    (if (janecjak-test-next-field grid (- (car my-location) 1) (cadr my-location))
                        'go-left
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-up go-down go-right))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-left)
                                (if (equal symb 'go-right)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-up go-down)))
                                )
                            )
                            'stay
                        )
                    )
                )
                (T
                    (nth (random 4) '(go-down go-right go-left go-up))
                )
            )
            )
            ((equal *janecjak-strategy* 3)
            (cond
            	((null ball-location) (janecjak-escape my-location grid))
            	((and
                     (janecjak-test-next-field grid (car my-location) (- (cadr my-location) 1))
                     (> (cadr my-location) (cadr ball-location))
                 )
                     'go-down
                )
            	((and
                     (janecjak-test-next-field grid (car my-location) (+ (cadr my-location) 1))
                     (< (cadr my-location) (cadr ball-location))
                 )
                     'go-up
                )
                ((and
                     (janecjak-test-next-field grid (- (car my-location) 1) (cadr my-location))
                     (> (car my-location) (car ball-location))
                 )
                     'go-left
                )
                ((and
                     (janecjak-test-next-field grid (+ (car my-location) 1) (cadr my-location))
                     (< (car my-location) (car ball-location))
                 )
                     'go-right
                )
                ((< (cadr my-location) (cadr ball-location))
                    (if (janecjak-test-next-field grid (car my-location) (+ (cadr my-location) 1))
                        'go-up
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-left go-right go-down))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-up)
                                (if (equal symb 'go-down)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-left go-right)))
                                )
                            )
                            'stay
                        )
                    )
                )
                ((< (car my-location) (car ball-location))
                    (if (janecjak-test-next-field grid (+ (car my-location) 1) (cadr my-location))
                        'go-right
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-up go-down go-left))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-right)
                                (if (equal symb 'go-left)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-up go-down)))
                                )
                            )
                            'stay
                        )
                    )
                )
                ((> (cadr my-location) (cadr ball-location))
                    (if (janecjak-test-next-field grid (car my-location) (- (cadr my-location) 1))
                        'go-down
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-left go-right go-up))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-down)
                                (if (equal symb 'go-up)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-left go-right)))
                                )
                            )
                            'stay
                        )
                    )
                )
                ((> (car my-location) (car ball-location))
                    (if (janecjak-test-next-field grid (- (car my-location) 1) (cadr my-location))
                        'go-left
                        (progn
                            (setf *janecjak-strategy* 2)
                            (let ((symb (nth (random 3) '(go-up go-down go-right))))
                                (setf *janecjak-strategy-symbol1* symb)
                                (setf *janecjak-strategy-symbol2* 'go-left)
                                (if (equal symb 'go-right)
                                    (setf *janecjak-strategy-symbol2* (nth (random 2) '(go-up go-down)))
                                )
                            )
                            'stay
                        )
                    )
                )
                (T
                    (nth (random 4) '(go-down go-right go-left go-up))
                )
            )
            )
        )
    )
)

    

(defmethod janecjak-predicate ((obj percept-object))
    (if (equal (percept-object-name obj) janecjak-agent-name)
        obj
        nil
    )
)

(defun janecjak-my-location (grid)
    (dotimes (numberx (car (array-dimensions grid)))
        (dotimes (numbery (cadr (array-dimensions grid)))
            (when (identify-in-list #'janecjak-predicate (aref grid numberx numbery))
                (return-from janecjak-my-location (list numberx numbery))
            )
        )
    )
    nil
)

(defun janecjak-ball-location (grid)
    (dotimes (numberx (car (array-dimensions grid)))
        (dotimes (numbery (cadr (array-dimensions grid)))
            (when (identify-in-list #'percept-object-ball-p (aref grid numberx numbery))
                (return-from janecjak-ball-location (list numberx numbery))
            )
        )
    )
    nil
)


(defun janecjak-opponent-locations (grid)
    (let ((locations nil))
        (dotimes (numberx (car (array-dimensions grid)))
            (dotimes (numbery (cadr (array-dimensions grid)))
                (when (identify-in-list #'janecjak-opponent-predicate (aref grid numberx numbery))
                    (setf locations (cons (cons numberx numbery) locations))
                )
            )
        )
        locations
    )
)

(defmethod janecjak-opponent-predicate ((obj percept-object))
    (if (and
            (percept-object-agent-p obj)
            (not (equal (percept-object-name obj) janecjak-agent-name))
        )
        obj
        nil
    )
)

(defun janecjak-test-next-field (grid x y)
    (let ((maxx (car (array-dimensions grid))) (maxy (cadr (array-dimensions grid))))
        (if (or
                (< x 0)
                (< y 0)
                (> x maxx)
                (> y maxy)
            )
            (return-from janecjak-test-next-field nil)
        )
    )
	(let ((obj (aref grid x y)))
        (if (or
                (null obj)
                (identify-in-list #'percept-object-ball-p obj)
            )
            T
            nil
        )
    )
)

(defun janecjak-nearest-opponent (my-location opponent-locations)
    (let ((min-distance 1000) (nearest nil))
        (dolist (opponent-location opponent-locations)
            (let ((current-distance (janecjak-distance (car my-location) (cadr my-location) (car opponent-location) (cdr opponent-location))))
                (if (< current-distance min-distance)
                    (progn
                        (setf min-distance current-distance)
                        (setf nearest (list (car opponent-location) (cdr opponent-location)))
                    )
                )
            )
        )
        nearest
    )
)

(defun janecjak-distance (x1 y1 x2 y2)
    (isqrt
        (+
            (expt (abs (- x1 x2)) 2)
            (expt (abs (- y1 y2)) 2)
        )
    )
)

(defun janecjak-escape (my-location grid)
    (let ((ball-location (janecjak-find-opponent-with-ball grid)))
        (cond
            ((equal (car my-location) (car ball-location))
                (cond
                    ((janecjak-test-next-field grid (+ (car my-location) 1) (cadr my-location))
                        'go-right
                    )
                    ((janecjak-test-next-field grid (- (car my-location) 1) (cadr my-location))
                        'go-left
                    )
                    (T
                        (if (< (cadr my-location) (cadr ball-location))
                            'go-down
                            'go-up
                        )
                    )
                )
            )
            ((equal (cadr my-location) (cadr ball-location))
                (cond
                    ((janecjak-test-next-field grid (car my-location) (+ (cadr my-location) 1))
                        'go-up
                    )
                    ((janecjak-test-next-field grid (car my-location) (- (cadr my-location) 1))
                        'go-down
                    )
                    (T
                        (if (< (car my-location) (car ball-location))
                            'go-left
                            'go-right
                        )
                    )
                )
            )
            (T
                (cond
                    ((and
                         (< (car my-location) (car ball-location))
                         (< (cadr my-location) (cadr ball-location))
                     )
                         (if (< (- (car ball-location) (car my-location) (- (cadr ball-location) (cadr my-location))))
                             (if (janecjak-test-next-field grid (car my-location) (- (cadr my-location) 1))
                                 'go-down
                                 'go-left
                             )
                             (if (janecjak-test-next-field grid (- (car my-location) 1) (cadr my-location))
                                 'go-left
                                 'go-down
                             )
                         )
                    )
                    ((and
                         (> (car my-location) (car ball-location))
                         (> (cadr my-location) (cadr ball-location))
                     )
                         (if (< (- (car my-location) (car ball-location) (- (cadr my-location) (cadr ball-location))))
                             (if (janecjak-test-next-field grid (car my-location) (+ (cadr my-location) 1))
                                 'go-up
                                 'go-right
                             )
                             (if (janecjak-test-next-field grid (+ (car my-location) 1) (cadr my-location))
                                 'go-right
                                 'go-up
                             )
                         )
                    )
                    ((and
                         (> (car my-location) (car ball-location))
                         (< (cadr my-location) (cadr ball-location))
                     )
                         (if (< (- (car my-location) (car ball-location) (- (cadr ball-location) (cadr my-location))))
                             (if (janecjak-test-next-field grid (car my-location) (- (cadr my-location) 1))
                                 'go-down
                                 'go-right
                             )
                             (if (janecjak-test-next-field grid (+ (car my-location) 1) (cadr my-location))
                                 'go-right
                                 'go-down
                             )
                         )
                    )
                    ((and
                         (< (car my-location) (car ball-location))
                         (> (cadr my-location) (cadr ball-location))
                     )
                         (if (< (- (car ball-location) (car my-location) (- (cadr my-location) (cadr ball-location))))
                             (if (janecjak-test-next-field grid (car my-location) (+ (cadr my-location) 1))
                                 'go-up
                                 'go-left
                             )
                             (if (janecjak-test-next-field grid (- (car my-location) 1) (cadr my-location))
                                 'go-left
                                 'go-up
                             )
                         )
                    )
                )
            )
        )
        ;'stay
    )
)

(defun janecjak-find-opponent-with-ball (grid)
    (dotimes (numberx (car (array-dimensions grid)))
        (dotimes (numbery (cadr (array-dimensions grid)))
            (when (identify-in-list #'janecjak-opponent-with-ball-predicate (aref grid numberx numbery))
                (return-from janecjak-find-opponent-with-ball (list numberx numbery))
            )
        )
    )
)

(defmethod janecjak-opponent-with-ball-predicate ((obj percept-object))
    (if (and
            (percept-object-agent-p obj)
            (percept-object-agent-has-ball obj)
            (not (equal (percept-object-name obj) janecjak-agent-name))
        )
        obj
        nil
    )
)

;; This is to be defined when designing a new student agent 
;
;(defstructure (my-agent    ; replace "my-agent" by your unique name, as e.g. FIT username
;                (:include db-agent 
;                  (body (make-my-agent-body))
;                  (program 'my-agent-program))
;                  (name "my-agent")) 
;  "Your agent for db-world.")
;
;(defstructure (my-agent-body 
;                (:include db-agent-body))
;  (slot1 default1)  ; any specific extra slots your agent's body would need
;  ...
;  (slotn defaultn))
;    ;
;    )
;
;(defun my-agent-program (percept)
;  (let ((agent-body (first percept)))    ; extracts agent body from percept
;    (setf percept (second percept))      ; extracts proper percept
 ;...
 ;...  here your program comes to calculate and return a proper action       
 ;...
; for example:
; (nth (random 4) '(go-left go-right go-up go-down))
;    ) )

;;; Any number of auxiliary functions can follow
;;; 
;;; To test run the game in single mode you perform
;;; (test-agent-mode-1 'your-agent-name)
;;; for example:
;;; (test-agent-mode-1 'ask-user-db-agent)
;;;
;;; To test run the game in competitive mode, we will perform
;;; (test-agent-mode-2 '(first-student-agent second-student-agent third-student-agent ...))
;;; for example:
;;; (test-agent-mode-2 '(ask-user-db-agent ask-user-db-agent))
;;; ==================================================================

;;; ==================================================================
;;; agent tests


(defun test-agent-mode-1 (student-agent)
  "returns t if the agent survives until the end and max-steps was not reached. Otherwise returns nil"
  (let* ((world (make-db-world :max-steps 400)))
    (add-agent world 'wait-and-throw-db-agent)
    (add-agent world 'wait-and-throw-db-agent)
    (add-agent world 'wait-and-throw-db-agent)
    (add-agent world student-agent)
    (initialize world)
    (run-environment world)
    (if (and (= 1 (agents-alive (db-world-agents world) world)) (find-student (get-percept-grid world))) t nil)))

(defun test-agent-mode-2 (agent-list)
  (let* ((world (make-db-world :game-mode competetive-mode :max-steps (* 100 (list-length agent-list)))))
    (dolist (agent agent-list)
      (add-agent world agent))
    (initialize world)
    (run-environment world)
    ;; print a table of results
    (let ((agents (db-world-agents world)))
      (sort agents #'(lambda (ag1 ag2) (> (agent-score ag1) (agent-score ag2))))
      (print-results agents))))

(defun print-results (agent-list)
  (format t "~&Results:~%")
  (dolist (agent agent-list)
    (format t "~A~%" agent)))


;;; ==================================================================
;;;; The ball definition


(defstructure (ball (:include object
    (alive? nil)
    (name "B") 
    (size 0.01)))
  "A ball used for hitting other agents")


;;; ==================================================================
;;;; Defining the generic functions


(defmethod termination? ((env db-world))
  "End when everyone dead except one or when"
  (or (and (eq (db-world-game-mode env) single-mode) 
           (or (> (environment-step env) (environment-max-steps env))
               (= 1 (agents-alive (db-world-agents env) env))
               (not (find-student (get-percept-grid env)))))
      (and (eq (db-world-game-mode env) competetive-mode) 
           (or (> (environment-step env) (environment-max-steps env))
               (= 1 (agents-alive (db-world-agents env) env))))))

(defmethod agents-alive (ag-list (env db-world))
  (if (not ag-list) 0
    (+ (if (agent-alive env (agent-body (car ag-list))) 1 0) 
       (agents-alive (cdr ag-list) env))))
   
(defmethod performance-measure ((env db-world) agent)
  "Score 10 for hitting a person and score 20 for each person out while still living."
  (+ (* (agent-hits env (agent-body agent)) 10) 
     (* (agent-outlived env (agent-body agent)) 20)))

(defmethod legal-actions ((env db-world))
  "In the dodgeball world, agents can move around, grab a ball and throw the ball."
  '(go-right go-left go-up go-down grab-ball throw-ball stay stop))


;;; ==================================================================
;;;; Actions


;;; ==================================================================
;;;; grab-ball


(defmethod grab-ball ((env db-world) agent-body &optional args)
  "Agent grabs the ball."
  (declare-ignore args) ;; They are used in other environments
  (let* ((loc (object-loc agent-body)) 
         (ball (ball-at-p env loc)))
    (when (and (agent-alive env agent-body) ball)
      (place-in-container ball agent-body env)
      (agent-got-ball env agent-body))))

(defun ball-at-p (env loc)
  (let* ((x (car loc)) 
         (y (cadr loc)) 
         (objs (objects-at env x y))
         (ball (contains-pred objs "B" #'(lambda (obj name) (equal (object-name obj) name)))))
    ball))

(defmethod objects-at ((env db-world) x y)
  (aref (db-world-grid env) x y))

(defun contains-pred (l o pred &optional (true nil))
  "returns the element if the list contains it. useless for nil element unless the optional true arg is given"
  (if (not l) 
      nil 
    (let ((c (car l))) 
      (if (funcall pred c o) 
          (if true t c)
        (contains-pred (cdr l) o pred true)))))


;;; ==================================================================
;;;; throw-ball
;;; Checks which squares the ball flies through. It hits any agents in the path with a certain probability
;;; The only function interesting for the student is 'go-through-dist-list. The others can be regarded as private.

(defun points-dist (point-from point-to)
  "(points-dist '(0 0) '(1 1))"
  (expt (+ 
      (expt (- (car point-from) (car point-to)) 2) 
      (expt (- (cadr point-from) (cadr point-to)) 2))
        0.5))

(defun signum (x) (if (zerop x) x (if (> x 0) 1 -1)))

(defun intersect-list (point-from point-to)
  (let* ((xf (car point-from))
         (yf (cadr point-from))
         (xt (car point-to))
         (yt (cadr point-to))
         (xlist (cross-list xf xt))
         (ylist (cross-list yf yt))
         (resl nil)
         (firstop (if (< xf xt) #'< #'>))
         (secop (if (< yf yt) #'< #'>)))
    (setq resl (sort  
                      (append (cross-where xlist t point-from point-to) (cross-where ylist nil point-from point-to))
                     (lambda (p1 p2) (if (funcall firstop (car p1) (car p2)) 
                                         t (if (eql (car p1) (car p2)) 
                                               (funcall secop (cadr p1) (cadr p2) ) nil )))))
    (setq resl (remove-dups resl))
    ))

(defun go-through-list (il pf)
  "parameters (intersection-list point-from)
returns an ordered list of squares that a ball thrown from a specific square will fly through, 
including the target square."
  (if (not il) nil
    (let ((nextl (car il))
          (restl (cdr il))
          newx newy)
          (if (wholep (car nextl))
              (if (wholep (cadr nextl))
                  (progn
                    (if (= (car nextl) (car pf)) 
                        (setf newx (floor (- (car nextl) 1)))
                      (setf newx (floor (car nextl))))
                    (if (= (cadr nextl) (cadr pf))
                        (setf newy (floor (- (cadr nextl) 1)))
                      (setf newy (floor (cadr nextl))))
                    (return-from go-through-list (cons `(,newx ,newy) (go-through-list (cdr il) `(,newx ,newy))))
                    )
                (progn
                  (setf newy (floor (cadr pf)))
                  (if (= (floor (car nextl)) (car pf))
                      (setf newx (floor (- (car nextl) 1)))
                    (setf newx (floor (car nextl))))
                  (return-from go-through-list (cons `(,newx ,newy) (go-through-list (cdr il) `(,newx ,newy))))
                  ))
            (progn ;whole-number intersection with a y-line
              (setf newx (floor (car pf)))
              (if (= (floor (cadr nextl)) (cadr pf)) ; floor function not needed here, probably
                  (setf newy (floor (- (cadr nextl) 1)))
                (setf newy (floor (cadr nextl))))
              (return-from go-through-list (cons `(,newx ,newy) (go-through-list (cdr il) `(,newx ,newy))))
              )))))

(defun wholep (num)
  (= (floor num) num))

(defun go-through-dist-list (pf pt &optional (gtl nil gtl-supplied-p))
  "parameters point-from, point-to. 
   Returns a list of squares the ball flies over together with their distance from the source square.
   Use this function when deciding where to throw the ball if unsure of the trajectory."
  (when (null gtl-supplied-p) (setf gtl (go-through-list (intersect-list pf pt) pf)))
  (let ((resl nil) (currcons nil) tmp)
    (if (null gtl)
        nil
      (cons (list (first gtl) (points-dist pf (first gtl))) (go-through-dist-list pf pt (rest gtl)))
      )))
    

(defun remove-dups (sortedl)
  "remove duplicities in the sorted list"
  (let ((newl nil) tmp)
    (dolist (x sortedl)
      (when (not (equalp x (car newl))) (push x newl)))
    (reverse newl)))

(defun ltoints (l)
  (mapcar #'toints l))

(defun toints (l)
    (list (floor (car l)) (floor (cadr l))))

(defun cross-list (fx tx)
  "point-from and point-to are squares in the grid. Imagine a line connecting centers of the squares"
  (let* ((res-list nil)
         (dif (- tx fx))
         (sigdif (signum dif))
         (timesdif (* dif sigdif))
         temp (rev t))
    (when (< tx fx) (setf temp fx) (setf fx tx) (setf tx temp) (setf rev nil)) ; reverse the output when done
    (dotimes (num timesdif nil) (push (+ fx 1 num) res-list))
    (if rev (reverse res-list) res-list)))

(defun cross-where (cross-list x? point-from point-to)
  "return coordinates of intersections with lines in cross-list. First add 0.5 to the point coords"
  (let ((mylist nil)
        (xf (+ 0.5 (car point-from)))
        (yf (+ 0.5 (cadr point-from)))
        (xt (+ 0.5 (car point-to)))
        (yt (+ 0.5 (cadr point-to))))
    (if x?
        (dolist (x cross-list) (setf mylist (cons `(,x 0 ,x 1 ,xf ,yf ,xt ,yt) mylist))) 
      (dolist (x cross-list) (setf mylist (cons `(0 ,x 1 ,x ,xf ,yf ,xt ,yt) mylist))))
    (reverse (mapcar #'(lambda (y) (apply #'get-intersection y)) mylist))))

(defun get-intersection (x1 y1 x2 y2 x3 y3 x4 y4)
  (let ((denom (- (* (- x1 x2) (- y3 y4)) (* (- y1 y2) (- x3 x4))))
        (ua-num (- (* (- (* x1 y2) (* y1 x2)) (- x3 x4)) (* (- x1 x2) (- (* x3 y4) (* y3 x4)))))
        (ub-num (- (* (- (* x1 y2) (* y1 x2)) (- y3 y4)) (* (- y1 y2) (- (* x3 y4) (* y3 x4))))))
    (cond 
     ((zerop denom) (if (zerop ua-num) 'all nil))
     (t (list (/ ua-num denom) (/ ub-num denom))))))

(defmethod fly-the-ball ((env db-world) ball point-from point-to)
  "Throw the ball towards the point-to. Any agent standing between point-from and point-to can be hit by the ball.
If the agent is hit, the ball drops on his square. The ball will hit the agent with probability depending on his distance
from the agent that threw the ball. Dist < 2 = 100% hit. Dist => 2, Dist < 5 = (10-dist)*10% hit. Dist >= 5 = 0% hit."
  (let ((gtl (go-through-dist-list point-from point-to))
        (agents (db-world-agents env)))
    (dolist (point-dist gtl)
      (let* ((ag-point (car point-dist))
             (ag-dist (cadr point-dist))
             (ag (contains-pred agents 
                                ag-point
                                #'(lambda (ag1 point) (equal (object-loc (agent-body ag1)) point)) ))
             (agb (if (eq ag nil) nil (agent-body ag))))
        (when (and agb (agent-alive env agb)
                   (or (< ag-dist 2) (and (< ag-dist 5) (>= (random 10) (floor ag-dist)))))
          ;;(format t "an agent was hit~%")
          (let* ((ag-source (contains-pred agents 
                                           point-from
                                           #'(lambda (ag1 point) (equal (object-loc (agent-body ag1)) point)) )))
            ;(print ag-source)
            (agent-scored-hit env (agent-body ag-source)))
          (agent-lost-life env agb )
          ;;(format  t "Putting ball at ~A~%." ag-point)
          (place-object ball ag-point env)
          (return-from fly-the-ball t)))))
  ;;(format  t "Putting ball at ~A~%." point-to)
  (place-object ball point-to env) 
  nil)

(defmethod throw-ball ((env db-world) agent-body x y &optional args)
  "Agent throws the ball and possibly hits another agent with a ball."
  (declare-ignore args) ;; They are used in other environments
  (let* ((loc (object-loc agent-body))
         (point-to (@ x y))
         (dims (array-dimensions (db-world-grid env)))
         (dimx (car dims))
         (dimy (cadr dims)))
    ;;(format t "x: ~A y: ~A~%" x y)
    (if (and (agent-alive env agent-body) (agent-has-ball env agent-body) (< x (- dimx 1)) (> x 0) (< y (- dimy 1)) (> y 0))
        ;; if the agent holds the ball and is not throwing into a wall, then:
      (let ((ball (car (object-contents agent-body))))
        ;;(format t "throwing ball~%")
        (setf (object-contents agent-body) nil)
        (setf (object-container ball) nil)
        
        (fly-the-ball env ball loc point-to)
        (agent-threw-ball env agent-body)
        ;; If point-to contains an agent, then hit the agent with some probability... 
        ;; Also try to hit the agents on the fly.
        ) (format t "Cannot throw the ball~%"))))


;;; ==================================================================
;;;; go-left,right,up,down, stay


(defmethod go-left ((env db-world) agent-body &optional (args 1))
  "Go args steps to the left."
  (and (agent-alive env agent-body) (not (agent-has-ball env agent-body )) (move-all-by env agent-body '(-1 0))))
         
(defmethod go-right ((env db-world) agent-body &optional (args 1))
  "Go args steps to the right."
  (and (agent-alive env agent-body) (not (agent-has-ball env agent-body )) (move-all-by env agent-body '(1 0))))

(defmethod go-up ((env db-world) agent-body &optional (args 1))
  "Go args steps up."
   (and (agent-alive env agent-body) (not (agent-has-ball env agent-body )) (move-all-by env agent-body '(0 1))))

(defmethod go-down ((env db-world) agent-body &optional (args 1))
  "Go args steps down"
   (and (agent-alive env agent-body) (not (agent-has-ball env agent-body )) (move-all-by env agent-body '(0 -1))))

(defmethod stay ((env db-world) agent-body &optional (args 1))
  "do not move."
  t)

(defmethod move-all-by ((env db-world) agent-body dir)
  "Move the agent and the ball if he has it"
  (move-object-by agent-body dir env)
  (when (and (> (length (object-contents agent-body)) 0) 
             (eq (car (object-contents agent-body)) (db-world-ball env)))
    (move-object-by (db-world-ball env) dir env))) 


;;; ==================================================================
;;;; Stop world evaluation


(defmethod stop ((env db-world) agent-body &optional args)
  "Stop db world execution. Use for debugging only."
  (setf (environment-max-steps env) 0))


;;; ==================================================================
;;;; Other code, replacing older methods and taking care of bumping agents


(defmethod print-structure ((object db-agent-body) stream)
  "Overload from grid-env: Show an object's name"
  (let ((name (or (object-name object) (type-of object)))
        (cont (object-contents object)))
    (if cont 
        (format stream "~A." name )
      (format stream "~A" name ))))

(defmethod print-structure ((object percept-object) stream)
  "Show an object's name"
    (format stream "~A" (percept-object-name object)))

(defmethod print-structure ((object percept-object-agent) stream)
  "Show an object's name"
    (format stream "~A-~A" (percept-object-name object) (percept-object-agent-lives object))
    (if (percept-object-agent-has-ball object) (format stream ".")))

(defmethod initialize ((env db-world))
  "Build a new environment with all the agents and objects in place.
  This gets passed an environment which may need to have the objects placed.
  See PARSE-SPECS below in this file for more on initialization."
  (unless (environment-initialized env)
    (call-next-method)
    ;; put all agents on random spaces
    ;;(format t "moving agents randomly")
    (loop for ag in (db-world-agents env) do (move-object-to (agent-body ag) (random-loc env :if 'free-loc?) env))
    ;; initialise the hits, outlived, lives and ball-holding alists
    (loop for ag in (db-world-agents env) do 
    	    (push (cons (agent-body ag) 3) (db-world-agents-lives env))
    	    (push (cons (agent-body ag) 0) (db-world-agents-hits env))
    	    (push (cons (agent-body ag) 0) (db-world-agents-outlived env))
    	    (push (cons (agent-body ag) nil) (db-world-agents-at-ball env))
    	    (push (cons (agent-body ag) nil) (db-world-agents-holding env)))))

(defmethod add-agent ((env db-world) ag)
  "add an agent to the world, on an arbitrary position"
  (push ag (db-world-aspec env)))

(defun my-copy-array (array)
  "http://lemonodor.com/archives/000100.html"
  (let (lin-array (dims (array-dimensions array)) lin-copied-array final-array)
    (setf lin-array (make-array (apply #'* dims) :displaced-to array))
    (setf lin-copied-array (copy-seq lin-array))
    (setf final-array (make-array dims :displaced-to lin-copied-array))))

(defun update-holding (env)
  "Update the counter that says how many turns some agent is holding the ball or standing on the ball's square. 
   If a limit of 3 is exceeded, kill the agent.
   Find agents that stand on the same square as is the ball"
  (dolist (agent (db-world-agents env))
    (if (or (agent-has-ball env (agent-body agent)) (ball-at-p env (object-loc (agent-body agent))))
      (agent-at-ball env (agent-body agent)) (agent-not-at-ball env (agent-body agent))))
  (increase-time-with-ball env))

(defmethod update-fn ((env db-world))
  "Modify the environment, based on agents actions. Also inhibit actions that would result in an agent crash"
  (update-holding env)
  (forbid-crashes env)
  ;; put the ball-throwing agents first:
  (deactivate-dead env)
  (sort-agents env) 
  (execute-agent-actions env))

(defun deactivate-dead (env)
  ; change the actions of dead agents to 'stay
  (dolist (agent (db-world-agents env))
    (when (not (agent-alive env (agent-body agent))) (setf (agent-action agent) 'stay))))

(defun sort-agents (env)
  (setf (db-world-agents env) (sort (db-world-agents env) #'(lambda (agx agy) (and (listp (agent-action agx)) (eq (car (agent-action agx)) 'throw-ball))
))))

(defun forbid-crashes (env)
  (let* ((grid (db-world-grid env))
         (agents (db-world-agents env))
         (want-to-grid (make-array (array-dimensions grid) :initial-element nil))
         (taken '(nil nil))
         (agents-want-to nil))
    
    (dotimes (numberx (car (array-dimensions grid)))
      (dotimes (numbery (cadr (array-dimensions grid)))
        (when (find-object-if #'obstacle-p (list numberx numbery) env)
          (setf (aref want-to-grid numberx numbery) taken))))
    ;; The algorithm decides whether an agent may move on a selected square
    ;; he may not if this square contains an obstacle, another agent that does not move
    ;; or is a target of another agent
    ;; if this forbidden square contains a ball, the ball is displaced on a random location
    
    ;; mark squares as interested
    ;; if no conflict, the agents may be moved
    ;; otherwise the agents that wanted to move there cannot do so and stay where they are (taken=1)
    ;; in such case the whole process must be redone for the remaining agents until there is no conflict.
    ;; all agents shall place a pointer to themselves on the square that interests them
    
    (dolist (agent agents)
      (let* ((loc (object-loc (agent-body agent)))
             (target (list (car loc) (cadr loc))))
        (case (op (agent-action agent))
          (go-up (setf (cadr target) (+ (cadr target) 1)))
          (go-down (setf (cadr target) (- (cadr target) 1)))
          (go-right (setf (car target) (+ (car target) 1)))
          (go-left (setf (car target) (- (car target) 1)))
          (otherwise t))
        (when (agent-alive env (agent-body agent))
          (push agent (aref want-to-grid (car target) (cadr target)))
          (push (cons agent target) agents-want-to))))
    
    ;; check the agent actions; the agents are in conses together with their target positions
    (let ((change t))
      (loop while change do
            (setf change nil)
            (dolist (agent-where agents-want-to)
              (let* ((tox (car (cdr agent-where)))
                     (toy (cadr (cdr agent-where)))
                     (loc (object-loc (agent-body (car agent-where)))))
                (when (and (not (member (agent-action (car agent-where)) '(bump stay throw-ball grab-ball stop)))
                           (> (list-length (aref want-to-grid tox toy)) 1))
                  (setf (aref want-to-grid (car loc) (cadr loc)) taken)
                  (setf change t)
                  (setf (agent-action (car agent-where)) 'bump)
                  (let ((ball (ball-at-p env (list tox toy))))
                    (when ball
                      (move-object-to ball (random-loc env :if 'free-loc?) env) ;move ball somewhere else
                    )))))))))


#|
;;; ==================================================================
;;;; testing code

(setf world (make-db-world))
(add-agent world 'ask-user-db-agent)
(add-agent world 'wait-and-throw-db-agent)
(add-agent world 'wait-and-throw-db-agent)
(initialize world)
(setf (db-world-max-steps world) 100)
(run-environment world)
(display-environment-snapshot world)

|#
