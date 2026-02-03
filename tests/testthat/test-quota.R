test_that("suggest_quota rounds up appropriately", {
  expect_equal(suggest_quota(50), 100)
  expect_equal(suggest_quota(150), 200)
  expect_equal(suggest_quota(300), 500)
  expect_equal(suggest_quota(800), 1000)
  expect_equal(suggest_quota(1500), 2000)
})

test_that("suggest_quota adds buffer", {
  # 400 vCPUs needed = 500 with 25% buffer
  expect_equal(suggest_quota(400), 500)

  # 480 vCPUs needed = 600 with buffer, rounds to 1000
  expect_equal(suggest_quota(480), 1000)
})

test_that("parse_memory handles different formats", {
  expect_equal(parse_memory("8GB"), 8)
  expect_equal(parse_memory("16GB"), 16)
  expect_equal(parse_memory("1024MB"), 1)
  expect_equal(parse_memory("2048MB"), 2)
  expect_equal(parse_memory(8), 8)
})

test_that("parse_memory errors on invalid input", {
  expect_error(parse_memory("invalid"))
  expect_error(parse_memory("8"))
})
