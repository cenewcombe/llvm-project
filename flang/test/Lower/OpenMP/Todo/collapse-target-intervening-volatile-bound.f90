! An inner collapsed loop bound that is host-evaluated for an enclosing
! omp.target must be recomputed in-region to build the intervening-code guard.
! A VOLATILE bound may change between the host evaluation and the in-region
! re-read, so the guard would target an iteration the loop never takes.

! RUN: %not_todo_cmd %flang_fc1 -emit-hlfir -fopenmp -o - %s 2>&1 | FileCheck %s

! CHECK: not yet implemented: collapsed loop nest with intervening code whose host-evaluated loop bound reads VOLATILE variable 'm'

subroutine repro_volatile(n, m, x)
  implicit none
  integer, intent(in) :: n
  integer, volatile :: m
  integer, intent(inout) :: x
  integer :: i, j

  !$omp target teams distribute parallel do collapse(2) map(tofrom:x)
  do i = 1, n
    do j = 1, m
      x = x + 1
    end do
    x = x + j
  end do
end subroutine
