;;; cl-typesetting copyright 2003-2004 Marc Battyani see license.txt for the details
;;; You can reach me at marc.battyani@fractalconcept.com or marc@battyani.net
;;; The homepage of cl-typesetting is here: http://www.fractalconcept.com/asp/html/cl-typesetting.html

;;; Thanks to Dmitri Ivanov for the splittable tables!

(in-package typeset)

(defvar *table* nil)

(defvar *table-row* nil)

(defclass table-cell ()
  ((content :accessor content :initarg :content)
   (box :accessor box)
   (width :accessor width :initform 0)
   (height :accessor height :initform 0)
   (background-color :accessor background-color :initform nil :initarg :background-color)
   (col-span :accessor col-span :initform 1 :initarg :col-span)
   (row-span :accessor row-span :initform 1 :initarg :row-span)))

(defclass table-row ()
  ((height :accessor height :initform nil :initarg :height)
   (splittable-p :accessor splittable-p :initform t :initarg :splittable-p)
   (background-color :accessor background-color :initform nil :initarg :background-color)
   (cells :accessor cells :initform () :initarg :cells)))

(defclass table (box v-mode-mixin)
  ((cols-widths :accessor col-widths :initform nil :initarg :col-widths)
   (border :accessor border :initform 1 :initarg :border)
   (border-color :accessor border-color :initform '(0 0 0) :initarg :border-color)
   (background-color :accessor background-color :initform nil :initarg :background-color)
   (padding :accessor padding :initform 1 :initarg :padding)
   (cell-padding :accessor cell-padding :initform 1 :initarg :cell-padding)
   (rows :accessor rows :initform ())))

(defclass multi-page-table (table)
 ((header :accessor header :initarg :header :initform nil) ; rows printed on each page
  (footer :accessor footer :initarg :footer :initform nil) ; rows printed on each page
  (rows-left :accessor rows-left :initform ())))

(defclass multi-page-row (table-row)
 ((parent :accessor parent :initform *table* :initarg :parent)
  ;; padding control - :first, :last or :single
  (position :initarg :position :initform nil) 
))

(defun add-table-row (row &optional (table *table*))
  (if (rows table)
      (setf (cdr (last (rows table))) (list row))
      (setf (rows table) (list row))))

(defun add-table-cell (cell &optional (row *table-row*))
  (if (cells row)
      (setf (cdr (last (cells row))) (list cell))
      (setf (cells row) (list cell))))

(defmethod dy ((row multi-page-row))
 ;;; Called by method (stroke (box vbox) x y) after the row is factored out
  (let* ((table (parent row))
         (border (border table)))
    (+ (height row) border (* 2 (cell-padding table))
       (case (slot-value row 'position)
         (:first  (+ border (padding table)))
         (:last   (padding table))
         (:single (+ border (* 2 (padding table))))
         (otherwise 0)))))

(defun first-or-self (arg)
 ;;; The first element of arg, if it is a list; else arg itself.
  ;; Code from Paradigms of AI Programming, Copyright (c) 1991 Peter Norvig
  (if (consp arg) (first arg) arg))

(defmacro cell-start-row-p (cell row)
  `(or (numberp (row-span ,cell))		; still untouched cell
       (eq (first-or-self (row-span ,cell)) ,row)))

(defmacro cell-end-row-p (cell row)
  `(and (consp (row-span ,cell))
        (eq (first (last (row-span ,cell))) ,row)))

(defun span-cell (rows cell col-number)
 ;;; Replace the cell's numeric row-span by the list of rows spanned
  ;; and add the cell into the cell list of each of these rows.
  ;; Args: rows    Table row sublist starting from the one where the cell was defined.
  ;;   col-number  Starts from zero.
  (setf (splittable-p (first rows)) nil)
  (loop for row in (rest rows)
        and i downfrom (1- (row-span cell)) above 0	;repeat (1- (row-span cell))
        collect row into rows-spanned
        when (> i 1)				; set all but last rows unsplittable
          do (setf (splittable-p row) nil)
        do
	(loop for j = 0 then (+ j (col-span c))
              for tail = (cells row) then (cdr tail);; hack for CLISP instead of for tail on (cells row)
              for c = (first tail)		; j is the column number of c
              while (and c (< j col-number))
              collect (first tail) into head
              finally				; insert cell between head and tail
              (setf (cells row) (nconc head (list cell) tail)))
        finally					; replace numeric row-span by the list
        (return (setf (row-span cell) (cons (first rows) rows-spanned)))))

(defun compute-row-size (table row &optional rows)
  (let ((full-size-offset (+ (border table) (* 2 (cell-padding table))))
        (height (or (height row) +huge-number+)))
    (loop with next-widths = (col-widths table)
          for cell in (cells row)
          and width = (or (pop next-widths) 0)	; in case less elements specified
          and col-number = 0 then (+ col-number col-span 1)
	  and cell-height = 0.0
          for col-span = (1- (col-span cell))
          and row-span = (row-span cell)
	  
	  ;; Adjust cell width for cells spanning multiple columns
          unless (zerop col-span)
            do (incf width (+ (* col-span full-size-offset)
                              (reduce #'+ next-widths :end col-span)))
               (setf next-widths (nthcdr col-span next-widths))

          ;; Fill cell with content if required
          when (cell-start-row-p cell row)
            do (setf (box cell) (make-filled-vbox (content cell) width height)
                     (width cell) width)
	    
          ;; A cell spanning several rows participates only in height calculation 
          ;; of the last row
          if (and (numberp row-span) (> row-span 1))
          do (span-cell rows cell col-number)
          else unless (height row)
            if (eql row-span 1)
            do (setq cell-height
		     (compute-boxes-natural-size (boxes (box cell)) #'dy))
            else if (cell-end-row-p cell row)
	    do (setq cell-height
		     (- (compute-boxes-natural-size (boxes (box cell)) #'dy)
			(reduce #'+ row-span
				:key #'height
			:end (1- (length row-span))
				:initial-value (* (1- (length row-span))
						  full-size-offset))))

	  maximize cell-height into max-height

          finally (setf height (+ (max (or (height row) 0.0) max-height) +epsilon+)))
    (setf (height row) height)
    (loop for cell in (cells row)
          for row-span = (row-span cell)
          if (eql row-span 1)
          do (setf (height cell) height
                   (dy (box cell)) height)
             (do-layout (box cell))
          else if (cell-end-row-p cell row)
          do (let ((height (reduce #'+ row-span :key #'height
                                   :initial-value (* (1- (length row-span))
                                                     full-size-offset))))
               (setf (height cell) height
                     (dy (box cell)) height)
               (do-layout (box cell))))
    height))

(defmethod compute-table-size (table)
  (loop for rows on (rows table)
        do (compute-row-size table (first rows) rows))
  (let ((nb-rows (length (rows table)))
	(nb-cols (length (col-widths table))))
    (setf (dx table)(+ (* 2 (padding table))
		       (* 2 nb-cols (cell-padding table))
		       (* (1+ nb-cols) (border table))
		       (reduce #'+ (col-widths table))
		       +epsilon+)
	  (dy table)(+ (* 2 (padding table))
		       (* 2 nb-rows (cell-padding table))
		       (* (1+ nb-rows) (border table))
		       (reduce #'+ (rows table) :key 'height)
		       +epsilon+))))

(defmethod compute-table-size :after ((table multi-page-table))
  (with-slots (rows rows-left header footer) table
    (setf rows-left rows)
    (dolist (row header) (compute-row-size table row header))
    (dolist (row footer) (compute-row-size table row footer))))
                
(defmethod v-split ((table multi-page-table) dx dy &optional v-align)
  "Factor out rows that fit and return as a first value."
  ;; Treat unsplittable rows as a single unit - for this purpose,
  ;; group the rows-left list into the following form:
  ;;
  ;;     ( (group1-height row1 row2 ...)
  ;;       (group2-height row7)
  ;;       (group3-height row8 row9 ...) )
  ;;
  (with-slots (header footer border padding cell-padding) table
    (loop with boxes = ()
	  with header+footer-height = (+ (reduce #'+ header :key #'dy)
					 (reduce #'+ footer :key #'dy))
	  with current-height = (+ border padding)
	  with available-height = (- dy header+footer-height)
	  with row-groups = (loop with height = 0
				  and  rows = ()
	
				  for row in (rows-left table)

				  do
				  (incf height (+ (height row)
						  (* 2 cell-padding)
						  border))
				  (push row rows)

				  when (splittable-p row)
				  collect (cons height (nreverse rows))
				  and do (setf height 0 rows nil))
	  with rows-remaining = (rows-left table)
	  
          for (group-height . rows) in row-groups
	  while (<= (+ current-height group-height) available-height)

	  do (dolist (r rows)
	       (push r boxes)
	       (pop rows-remaining))
	  (incf current-height group-height)
	  
	  finally
	  (when boxes
	    (setq boxes (append header (nreverse boxes) footer))
	    ;; reduce rows to output
	    (setf (rows-left table) rows-remaining)
	    ;; reduce space required by table (don't subtract header/footer)
	    (decf (slot-value table 'dy) current-height)
            (let ((first (first boxes))
                  (last (first (last boxes))))
              (setf (slot-value first 'position) :first
                    (slot-value last 'position) (if (eq first last) :single :last)))
	    (return (values boxes
			    rows-remaining
			    (- dy current-height header+footer-height))))
	  (return (values nil rows-remaining dy)))))

(defmethod dy :around ((table multi-page-table))
  (with-slots (header footer) table
    (+ (call-next-method)
       (reduce #'+ header :key #'dy)
       (reduce #'+ footer :key #'dy))))

(defmethod boxes-left ((table multi-page-table))
  (rows-left table))

(defmethod stroke ((row multi-page-row) x y)
  (let* ((table (parent row))
         (position (slot-value row 'position))
         (border (border table))
         (padding (padding table))
         (row-y (case position ((:first :single) (- y border padding)) (otherwise y)))
         (cell-padding (cell-padding table))
         (cell-offset (+ cell-padding border))
         (full-size-offset (+ cell-offset cell-padding)))
    ;; Provide outer colorful padding which does not breach the border
    (when (and (background-color table) (not (zerop padding)) (zerop border))
      (let ((height (height row)))
        (pdf:with-saved-state
          (pdf:set-color-fill (background-color table))
          (case position
            ((:first :single)							; top  
             (pdf:basic-rect x y (dx table) (- padding))
             (pdf:fill-path)))
          (pdf:basic-rect x row-y padding (- (+ height full-size-offset)))	; left
          (pdf:fill-path)
          (pdf:basic-rect (+ x (dx table)) row-y
                          (- padding) (- (+ height full-size-offset)))		; right
          (pdf:fill-path)
          (case position
            ((:last :single)							; bottom
             (pdf:basic-rect x (- row-y height full-size-offset)
                             (dx table) (- padding))
             (pdf:fill-path))) )))
	
    (loop for cell-x = (+ x padding border) then (+ cell-x width full-size-offset)
          and cell in (cells row)
          for width = (width cell)
          and height = (height cell)
          when (cell-start-row-p cell row)
          do (pdf:with-saved-state
               (pdf:translate cell-x row-y)
               (pdf:with-saved-state
                 (let ((background-color (or (background-color cell)
                                             (background-color row)
                                             (background-color table))))
                   (when background-color
                     (pdf:set-color-fill background-color)
                     (pdf:basic-rect 0 0 (+ width full-size-offset)
                                     (- (+ height full-size-offset)))
                     (pdf:fill-path)))
                 (unless (zerop border)
                   (pdf:set-line-width border)
                   (pdf:set-gray-stroke 0)
                   (pdf:basic-rect 0 0 (+ width full-size-offset)(- (+ height full-size-offset)))
                   (pdf:stroke)))
               (stroke (box cell) cell-offset (- cell-offset))))))

(defmethod stroke ((table table) x y)
  (let* ((padding (padding table))
         (border (border table)))
    (when (background-color table)
      (pdf:with-saved-state
        (pdf:set-color-fill (background-color table))
        (if (or (zerop padding) (zerop border))
            (pdf:basic-rect x y (dx table) (- (dy table)))
            ;; External colorful padding should not breach border
            (pdf:basic-rect (+ x padding border) (- y padding border)
                            (- (dx table) (* 2 (+ padding border)))
                            (- (* 2 (+ padding border)) (dy table))))
        (pdf:fill-path)))
    (loop with cell-padding = (cell-padding table)
          with cell-offset = (+ cell-padding border)
          with full-size-offset = (+ cell-offset cell-padding)
          for row in (rows table)
          for row-y = (- y padding border) then (- row-y height full-size-offset)
          and height = (height row)
          do (loop for cell-x = (+ x padding border) then (+ cell-x width full-size-offset)
                   for cell in (cells row)
                   for width = (width cell)
                   for height = (height cell)
                   when (cell-start-row-p cell row)
                   do (pdf:with-saved-state
                        (pdf:translate cell-x row-y)
                        (pdf:with-saved-state
                          (when (or (background-color cell)(background-color row))
                            (pdf:set-color-fill (or (background-color cell)
                                                    (background-color row)))
                            (pdf:basic-rect 0 0 (+ width full-size-offset)
                                            (- (+ height full-size-offset)))
                            (pdf:fill-path))
                          (unless (zerop border)
                            (pdf:set-line-width (border table))
                            (pdf:set-gray-stroke 0)
                            (pdf:basic-rect 0 0 (+ width full-size-offset)
                                            (- (+ height full-size-offset)))
                            (pdf:stroke)))
                        (stroke (box cell) cell-offset (- cell-offset)))))))

;;; Convenience macros 

(defmacro table ((&key col-widths
                       (padding 5) (cell-padding 2)
                       (border 1) (border-color #x00000) 
		       background-color
                       header footer
                       inline (splittable-p (or header footer)))
		 &body body)
  (with-gensyms (hbox)
    `(let* ((*table* (make-instance (if ,splittable-p 'multi-page-table 'table)
                                    ,@(when header `((:header ,header)))
                                    ,@(when footer `((:footer ,footer)))
                                    :col-widths ,col-widths
                                    :padding ,padding :cell-padding ,cell-padding
                                    :background-color ,background-color
				    :border ,border :border-color ,border-color))
	    ,@(unless inline `((,hbox (make-instance 'hbox :boxes
				       (list (make-hfill-glue) *table* (make-hfill-glue))
				       :adjustable-p t)))))
      (add-box ,(if inline '*table* hbox))
      ,@body
      (compute-table-size *table*)
      ,@(unless inline `((compute-natural-box-size ,hbox)))
      *table*)))

(defmacro header-row ((&rest args) &body body)
  `(let* ((*table-row* (make-instance 'multi-page-row :splittable-p nil ;:position :first 
                                      ,@args)))
    (setf (header *table*) (nconc (header *table*) (list *table-row*)))
    ,@body
    *table-row*))

(defmacro footer-row ((&rest args) &body body)
  `(let* ((*table-row* (make-instance 'multi-page-row :splittable-p nil ;:position :last
                                      ,@args)))
    (setf (footer *table*) (nconc (footer *table*) (list *table-row*)))
    ,@body
    *table-row*))

(defmacro row ((&rest args) &body body)
  `(let ((*table-row* (make-instance (if (typep *table* 'multi-page-table)
                                         'multi-page-row
                                         'table-row)
                                     ,@args)))
     (add-table-row *table-row*)
     ,@body
     *table-row*))

(defmacro cell ((&rest args) &body body)
  `(add-table-cell (make-instance 'table-cell :content (compile-text () ,@body) ,@args)))

#|
;(let ((pdf:*page*(setq content
(defun make-test-table (&optional (inline t) (splittable-p nil) (border 1/2))
  (typeset:table (:col-widths '(20 40 60 80 120)
                  :background-color :yellow :border border
                  :inline inline :splittable-p splittable-p)
    (typeset::row (:background-color :green)
      (typeset:cell (:row-span 2 :background-color :blue)
                    "1,1 2,1  row-span 2")
      (typeset:cell () "1,2")
      (typeset:cell (:col-span 2 :row-span 3 :background-color :red)
                    "1,3 1,4 - 3,3 3,4  col-span 2 row-span 3")
      (typeset:cell () "1,5"))
    (typeset::row ()
      (typeset:cell () "2,2")
      (typeset:cell (:row-span 2 :background-color :blue) "2,5 3,5  row-span 2"))
    (typeset::row (:background-color :green)
      (typeset:cell (:col-span 2) "3,1 3,2  col-span 2"))
    (typeset::row ()
      (typeset:cell () "4,1")
      (typeset:cell () "4,2")
      (typeset:cell () "4,3")
      (typeset:cell () "4,4")
      (typeset:cell () "4,5"))
) )

(defun test-table (table
                   &optional (file (lw:current-pathname "../examples/test-table.pdf"))
                   &aux (margins '(72 72 72 50)))
  (with-document ()
    (let ((content (compile-text ()
                     (setq table (make-test-table t nil))
                     (make-test-table t nil 0)
                     (vspace 280)
                     ;(setq table (make-test-table t t 0))
                     ;(add-box (make-test-table t t))
                  )))
      (draw-pages content :margins margins)); :header header :footer footer) ;:break :after
    (draw-pages (setq table (make-test-table t t 1)) :margins margins)
    (when pdf:*page* (typeset::finalize-page pdf:*page*))
    (pdf:write-document file))
  table)

(setq table (test-table nil))
 |#