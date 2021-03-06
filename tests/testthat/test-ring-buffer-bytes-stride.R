context("stride")

test_that("empty", {
  buf <- ring_buffer_bytes(100, 5)

  expect_equal(buf$stride(), 5)

  expect_equal(buf$size(TRUE), 500L)
  expect_equal(buf$size(FALSE), 100L)
  expect_equal(buf$size(), 100L)

  expect_equal(buf$used(TRUE), 0L)
  expect_equal(buf$used(FALSE), 0L)
  expect_equal(buf$used(), 0L)

  expect_equal(buf$free(TRUE), 500L)
  expect_equal(buf$free(FALSE), 100L)
  expect_equal(buf$free(), 100L)

  expect_equal(buf$buffer_data(), raw(500))
  expect_equal(buf$bytes_data(), 501L)

  expect_equal(buf$head_pos(TRUE), 0L)
  expect_equal(buf$head_pos(FALSE), 0L)
  expect_equal(buf$head_pos(), 0L)

  expect_equal(buf$tail_pos(TRUE), 0L)
  expect_equal(buf$tail_pos(FALSE), 0L)
  expect_equal(buf$tail_pos(), 0L)

  expect_true(buf$empty())
  expect_false(buf$full())
})

test_that("memset", {
  size <- 100L
  stride <- 5L
  buf <- ring_buffer_bytes(100, 5)

  ## First, set a few entries to something nonzero:
  n <- 3L
  expect_equal(buf$set(as.raw(1), n), n * stride)

  ## Lots of checking of the state of the buffer:
  expect_false(buf$empty())
  expect_false(buf$full())

  expect_equal(buf$size(TRUE), size * stride)
  expect_equal(buf$size(FALSE), size)
  expect_equal(buf$size(), size)

  expect_equal(buf$used(TRUE), n * stride)
  expect_equal(buf$used(FALSE), n)
  expect_equal(buf$used(), n)

  expect_equal(buf$free(TRUE), size * stride - n * stride)
  expect_equal(buf$free(FALSE), size - n)
  expect_equal(buf$free(), size - n)

  expect_equal(buf$buffer_data(),
               pad(as.raw(rep(1, n * stride)), size * stride))
  expect_equal(buf$bytes_data(), size * stride + 1)

  expect_equal(buf$head_pos(TRUE), n * stride)
  expect_equal(buf$head_pos(FALSE), n)
  expect_equal(buf$head_pos(), n)

  expect_equal(buf$tail_pos(TRUE), 0L)
  expect_equal(buf$tail_pos(FALSE), 0L)
  expect_equal(buf$tail_pos(), 0L)

  ## Read a bit of the buffer and make sure that we're OK here.
  expect_equal(buf$read(0), raw())
  expect_equal(buf$read(1), as.raw(rep(1, stride)))
  expect_equal(buf$read(n), as.raw(rep(1, n * stride)))
  expect_error(buf$read(n + 1),
               "Buffer underflow")

  ## And check the tail offset works as expected
  expect_equal(buf$tail_offset_data(0), as.raw(rep(1, stride)))
  expect_equal(buf$tail_offset_data(n - 1), as.raw(rep(1, stride)))
  expect_error(buf$tail_offset_data(n),
               "Buffer underflow")

  ## Then, destructive modification: read a set of bytes:
  expect_equal(buf$take(0), raw())
  expect_equal(buf$take(1), as.raw(rep(1, stride)))

  expect_false(buf$empty())
  expect_false(buf$full())

  expect_equal(buf$head_pos(TRUE), n * stride)
  expect_equal(buf$head_pos(FALSE), n)
  expect_equal(buf$head_pos(), n)

  expect_equal(buf$tail_pos(TRUE), stride)
  expect_equal(buf$tail_pos(FALSE), 1L)
  expect_equal(buf$tail_pos(), 1L)

  expect_equal(buf$used(TRUE), (n - 1) * stride)
  expect_equal(buf$used(FALSE), n - 1)

  expect_equal(buf$free(TRUE), (size - n + 1) * stride)
  expect_equal(buf$free(FALSE), size - n + 1)

  expect_equal(buf$tail_offset_data(0), as.raw(rep(1, stride)))
  expect_equal(buf$tail_offset_data(n - 2), as.raw(rep(1, stride)))
  expect_error(buf$tail_offset_data(n - 1),
               "Buffer underflow")

  ## Read the rest:
  expect_equal(buf$take(n - 1),
               as.raw(rep(1, (n - 1) * stride)))

  expect_true(buf$empty())
  expect_false(buf$full())

  expect_equal(buf$head_pos(TRUE), n * stride)
  expect_equal(buf$head_pos(FALSE), n)
  expect_equal(buf$tail_pos(TRUE), n * stride)
  expect_equal(buf$tail_pos(FALSE), n)
  expect_equal(buf$used(TRUE), 0)
  expect_equal(buf$used(FALSE), 0)
  expect_equal(buf$free(TRUE), size * stride)
  expect_equal(buf$free(FALSE), size)
})

test_that("incorrect push", {
  buf <- ring_buffer_bytes(100, 5)
  expect_error(buf$push(as.raw(rep(1, 3))), "Incorrect size data")
  expect_true(all(buf$buffer_data() == as.raw(0L)))
})
