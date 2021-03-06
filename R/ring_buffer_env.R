##' An environment based ring buffer.  In contrast with the bytes
##' buffer, this one is truely circular, implemented as a pair of
##' doubly linked lists.
##'
##' @title Environment-based ring buffer
##' @param size The number of entries the buffer can contain.
##' @export
##' @author Rich FitzJohn
##' @examples
##' buf <- ring_buffer_env(10)
##' buf$push(1:10)
##' buf$take(3)
##' buf$push(11:15)
##' buf$take(2)
ring_buffer_env <- function(size) {
  .R6_ring_buffer_env$new(size)
}

## TODO: implement growth, which is fairly easy to do here; we break
## the ring and splice in another doubly linked list.

## There is an interface issue here that I need to deal with once I
## have the basic logic working; is the point of the buffer to
## implement a FIFO queue, or something more general?  In which case
## what do we do about things like the special treatment of head and
## tail for the case of using this like a FIFO/buffer.  The other
## thing I wonder about is whether it's OK to expose the head/tail
## thing or if we should abstract that away...

## TODO: Throughout, it is possible that any error in the assignment
## (probably via an R issue, object not being found etc) leaves the
## size element corrupt.  I'd like to drop this entirely I think, in
## favour of an odometer based counter.  Once I get some decent tests
## implemented I can try and swap that out.  When done, the lookups
## for capacity will be all O(n) which is a bit bad but probably a
## reasonable price to pay for simpler and more robust code.

ring_buffer_env_create <- function(size) {
  head <- prev <- NULL
  for (i in seq_len(size)) {
    x <- new.env(parent=emptyenv())
    if (is.null(prev)) {
      head <- x
    } else {
      prev$.next <- x
      x$.prev <- prev
    }
    prev <- x
  }

  x$.next <- head
  head$.prev <- x
  head$.size <- as.integer(size)
  head$.used <- 0L

  head
}

ring_buffer_env_duplicate <- function(buffer) {
  ret <- ring_buffer_env(buffer$size())

  ## To *truely* duplicate the buffer, we need to advance the pointers
  ## a little.
  tail <- ret$tail
  for (i in seq_len(buffer$tail_pos())) {
    tail <- tail$.prev
  }
  ret$head <- ret$tail <- tail

  tail <- buffer$tail
  for (i in seq_len(buffer$used())) {
    ret$push(tail$data, FALSE)
    tail <- tail$.next
  }

  ret
}

##' @importFrom R6 R6Class
.R6_ring_buffer_env <- R6::R6Class(
  "ring_buffer_env",
  ## need to implement our own clone method as the default R6 one is
  ## not going to cut it, given everything inside the class is a
  ## reference.
  cloneable=FALSE,

  public=list(
    buffer=NULL,
    head=NULL,
    tail=NULL,

    initialize=function(size) {
      self$buffer <- ring_buffer_env_create(size)
      self$reset()
    },

    reset=function() {
      self$head <- self$buffer
      self$tail <- self$buffer
      self$buffer$.used <- 0L
    },

    duplicate=function() {
      ring_buffer_env_duplicate(self)
    },

    size=function() self$buffer$.size,
    ## bytes_data
    ## stride
    used=function() self$buffer$.used,
    free=function() self$size() - self$used(),

    empty=function() self$used() == 0L,
    full=function() self$used() == self$size(),

    ## Mostly debugging:
    head_pos=function() {
      ring_buffer_env_distance_forward(self$buffer, self$head)
    },
    tail_pos=function() {
      ring_buffer_env_distance_forward(self$buffer, self$tail)
    },

    head_data=function() {
      ring_buffer_env_check_underflow(self, 1L)
      self$head$.prev$data
    },
    tail_data=function() {
      ring_buffer_env_check_underflow(self, 1L)
      self$tail$data
    },

    ## Start getting strong divergence here:
    set=function(data, n) {
      for (i in seq_len(min(n, self$size))) {
        ring_buffer_env_write_to_head(self, data)
      }
    },

    ## TODO: What about writing *single* things to the head and tail
    ## here?  The loop here is likely to be very annoying!  In some
    ## ways the loop is the natural analogue of memcpy but it's not
    ## really needed either.
    ##
    ## It will be probably useful on occassion to add a data.frame
    ## here row-by-row and things like that.  So we might have to make
    ## this one generic -- or find something that makes things
    ## iterable.
    push=function(data, iterate=TRUE) {
      if (iterate) {
        for (el in data) {
          ring_buffer_env_write_to_head(self, el)
        }
      } else {
        ring_buffer_env_write_to_head(self, data)
      }
    },

    take=function(n) {
      dat <- ring_buffer_env_read_from_tail(self, n)
      self$tail <- dat[[2L]]
      self$buffer$.used <- self$buffer$.used - as.integer(n)
      dat[[1L]]
    },

    read=function(n) ring_buffer_env_read_from_tail(self, n)[[1L]],

    copy=function(dest, n) {
      ring_buffer_env_check_underflow(self, n)

      tail <- self$tail
      for (i in seq_len(n)) {
        dest$push(tail$data)
        tail <- tail$.next
      }

      self$tail <- tail
      self$buffer$.used <- self$buffer$.used - as.integer(n)
    },

    head_offset_data=function(n) {
      ring_buffer_env_check_underflow(self, n + 1L)
      ring_buffer_env_move_backward(self$head$.prev, n)$data
    },
    tail_offset_data=function(n) {
      ring_buffer_env_check_underflow(self, n + 1L)
      ring_buffer_env_move_forward(self$tail, n)$data
    },

    ## This is the unusual direction...
    take_head=function(n) {
      dat <- ring_buffer_env_read_from_head(self, n)
      self$head <- dat[[2L]]
      self$buffer$.used <- self$buffer$.used - as.integer(n)
      dat[[1L]]
    },

    read_head=function(n) {
      ring_buffer_env_read_from_head(self, n)[[1L]]
    },

    ## This might come out as simply a free S3 method/function
    to_list=function() {
      ring_buffer_env_read_from_tail(self, self$used())[[1L]]
    }
  ))

ring_buffer_env_read_from_tail <- function(buf, n) {
  ring_buffer_env_check_underflow(buf, n)
  tail <- buf$tail
  ret <- vector("list", n)
  for (i in seq_len(n)) {
    ret[[i]] <- tail$data
    tail <- tail$.next
  }
  list(ret, tail)
}

ring_buffer_env_read_from_head <- function(buf, n) {
  ring_buffer_env_check_underflow(buf, n)
  head <- buf$head

  ret <- vector("list", n)
  for (i in seq_len(n)) {
    head <- head$.prev
    ret[[i]] <- head$data
  }
  list(ret, head)
}

ring_buffer_env_write_to_head <- function(buf, data) {
  buf$head$data <- data
  buf$head <- buf$head$.next
  if (buf$buffer$.used < buf$size()) {
    buf$buffer$.used <- buf$buffer$.used + 1L
  } else {
    buf$tail <- buf$tail$.next
  }
}

ring_buffer_env_check_underflow <- function(obj, requested) {
  ## TODO: Perhaps an S3 condition?
  if (requested > obj$used()) {
    stop(sprintf("Buffer underflow: requested %d, available %d",
                 requested, obj$used()))
  }
}

ring_buffer_env_distance_forward <- function(head, target) {
  i <- 0L
  while (!identical(target, head)) {
    i <- i + 1L
    head <- head$.next
  }
  i
}

ring_buffer_env_distance_backward <- function(tail, target) {
  i <- 0L
  while (!identical(target, tail)) {
    i <- i + 1L
    tail <- tail$.prev
  }
  i
}

ring_buffer_env_move_forward <- function(x, n) {
  for (i in seq_len(n)) {
    x <- x$.next
  }
  x
}

ring_buffer_env_move_backward <- function(x, n) {
  for (i in seq_len(n)) {
    x <- x$.prev
  }
  x
}
