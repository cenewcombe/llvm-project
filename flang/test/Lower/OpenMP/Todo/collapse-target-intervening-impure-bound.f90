! An inner collapsed loop bound that is host-evaluated for an enclosing
! omp.target must be recomputed in-region to build the intervening-code guard.
! That is only valid if re-evaluating the bound yields the same value, so an
! impure call in the bound is rejected instead of silently mis-guarding.

! RUN: %not_todo_cmd %flang_fc1 -emit-hlfir -fopenmp -o - %s 2>&1 | FileCheck %s

! CHECK: not yet implemented: collapsed loop nest with intervening code whose host-evaluated loop bound calls impure procedure 'next_bound'

module m
  implicit none
  integer :: counter = 0
  !$omp declare target(counter)
contains
  impure integer function next_bound()
    !$omp declare target
    counter = counter + 1
    next_bound = counter
  end function
end module

subroutine repro_impure(n, x)
  use m
  implicit none
  integer, intent(in) :: n
  integer, intent(inout) :: x
  integer :: i, j

  !$omp target teams distribute parallel do collapse(2) map(tofrom:x)
  do i = 1, n
    do j = 1, next_bound()
      x = x + 1
    end do
    x = x + j
  end do
end subroutine
