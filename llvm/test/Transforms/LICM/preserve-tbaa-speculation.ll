; RUN: opt -passes='loop-mssa(licm)' -S < %s | FileCheck %s

; A conditionally-executed load is hoisted speculatively, so LICM drops metadata
; that would imply UB in the new position. A whole-object load of a global of
; non-aggregate type is an exception: its type cannot have been established by
; the condition, so !tbaa is kept.

@g = external global double
@u = external global { double }
@p = external global ptr
@a = external global [4 x double]

; CHECK-LABEL: @whole_scalar_global(
; CHECK: entry:
; CHECK-NEXT: %v = load double, ptr @g, align 8, !tbaa [[TAG:![0-9]+]]{{$}}
define double @whole_scalar_global(i32 %n, i1 %c) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %acc = phi double [ 0.000000e+00, %entry ], [ %acc.next, %latch ]
  br i1 %c, label %guarded, label %latch

guarded:
  %v = load double, ptr @g, align 8, !tbaa !4
  br label %latch

latch:
  %t = phi double [ %v, %guarded ], [ 0.000000e+00, %loop ]
  %acc.next = fadd double %acc, %t
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  %res = phi double [ %acc.next, %latch ]
  ret double %res
}

; A struct-path tag names a field of a larger object, which is the case the drop
; exists to protect.
; CHECK-LABEL: @struct_path_tag(
; CHECK: entry:
; CHECK-NEXT: %v = load double, ptr @u, align 8{{$}}
define double @struct_path_tag(i32 %n, i1 %c) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %acc = phi double [ 0.000000e+00, %entry ], [ %acc.next, %latch ]
  br i1 %c, label %guarded, label %latch

guarded:
  %v = load double, ptr @u, align 8, !tbaa !6
  br label %latch

latch:
  %t = phi double [ %v, %guarded ], [ 0.000000e+00, %loop ]
  %acc.next = fadd double %acc, %t
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  %res = phi double [ %acc.next, %latch ]
  ret double %res
}

; The access type does not match the global's value type, so this is not a
; whole-object access.
; CHECK-LABEL: @type_mismatch(
; CHECK: entry:
; CHECK-NEXT: %v = load i32, ptr @g, align 8{{$}}
define i32 @type_mismatch(i32 %n, i1 %c) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %acc = phi i32 [ 0, %entry ], [ %acc.next, %latch ]
  br i1 %c, label %guarded, label %latch

guarded:
  %v = load i32, ptr @g, align 8, !tbaa !7
  br label %latch

latch:
  %t = phi i32 [ %v, %guarded ], [ 0, %loop ]
  %acc.next = add i32 %acc, %t
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  %res = phi i32 [ %acc.next, %latch ]
  ret i32 %res
}

; A whole-object load of an aggregate is excluded even though base and access
; types match, since a struct's storage may be reinterpreted.
; CHECK-LABEL: @whole_aggregate_global(
; CHECK: entry:
; CHECK-NEXT: %v = load { double }, ptr @u, align 8{{$}}
define double @whole_aggregate_global(i32 %n, i1 %c) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %acc = phi double [ 0.000000e+00, %entry ], [ %acc.next, %latch ]
  br i1 %c, label %guarded, label %latch

guarded:
  %v = load { double }, ptr @u, align 8, !tbaa !11
  %e = extractvalue { double } %v, 0
  br label %latch

latch:
  %t = phi double [ %e, %guarded ], [ 0.000000e+00, %loop ]
  %acc.next = fadd double %acc, %t
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  %res = phi double [ %acc.next, %latch ]
  ret double %res
}

; getUnderlyingObject looks through the GEP to @a, whose value type is the array
; rather than the element type, so this is not a whole-object access.
; CHECK-LABEL: @array_element(
; CHECK: entry:
; CHECK-NEXT: %v = load double, ptr getelementptr {{.*}}@a{{.*}}, align 8{{$}}
define double @array_element(i32 %n, i1 %c) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %acc = phi double [ 0.000000e+00, %entry ], [ %acc.next, %latch ]
  br i1 %c, label %guarded, label %latch

guarded:
  %v = load double, ptr getelementptr inbounds ([4 x double], ptr @a, i64 0, i64 1), align 8, !tbaa !4
  br label %latch

latch:
  %t = phi double [ %v, %guarded ], [ 0.000000e+00, %loop ]
  %acc.next = fadd double %acc, %t
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  %res = phi double [ %acc.next, %latch ]
  ret double %res
}

; An alloca is not covered yet: its effective type can change across lifetimes.
; CHECK-LABEL: @alloca_not_yet(
; CHECK: store double 1.000000e+00, ptr %q, align 8
; CHECK-NEXT: %v = load double, ptr %q, align 8{{$}}
define double @alloca_not_yet(i32 %n, i1 %c) {
entry:
  %q = alloca double, align 8
  store double 1.000000e+00, ptr %q, align 8
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %acc = phi double [ 0.000000e+00, %entry ], [ %acc.next, %latch ]
  br i1 %c, label %guarded, label %latch

guarded:
  %v = load double, ptr %q, align 8, !tbaa !4
  br label %latch

latch:
  %t = phi double [ %v, %guarded ], [ 0.000000e+00, %loop ]
  %acc.next = fadd double %acc, %t
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  %res = phi double [ %acc.next, %latch ]
  ret double %res
}

; !tbaa is spared but other UB-implying metadata is still dropped.
; CHECK-LABEL: @other_metadata_still_dropped(
; CHECK: entry:
; CHECK-NEXT: %v = load ptr, ptr @p, align 8, !tbaa [[PTAG:![0-9]+]]{{$}}
define ptr @other_metadata_still_dropped(i32 %n, i1 %c) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %i.next, %latch ]
  %acc = phi ptr [ null, %entry ], [ %t, %latch ]
  br i1 %c, label %guarded, label %latch

guarded:
  %v = load ptr, ptr @p, align 8, !tbaa !9, !noundef !10
  br label %latch

latch:
  %t = phi ptr [ %v, %guarded ], [ %acc, %loop ]
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %exit, label %loop

exit:
  %res = phi ptr [ %t, %latch ]
  ret ptr %res
}

!0 = !{!"root"}
!1 = !{!"omnipotent char", !0, i64 0}
!2 = !{!"double", !1, i64 0}
!3 = !{!"int", !1, i64 0}
!4 = !{!2, !2, i64 0}
!5 = !{!"struct U", !2, i64 0}
!6 = !{!5, !2, i64 0}
!7 = !{!3, !3, i64 0}
!8 = !{!"any pointer", !1, i64 0}
!9 = !{!8, !8, i64 0}
!10 = !{}
!11 = !{!5, !5, i64 0}

; CHECK-DAG: [[TAG]] = !{[[DOUBLE:![0-9]+]], [[DOUBLE]], i64 0}
; CHECK-DAG: [[DOUBLE]] = !{!"double", {{.*}}}
; CHECK-DAG: [[PTAG]] = !{[[ANYPTR:![0-9]+]], [[ANYPTR]], i64 0}
; CHECK-DAG: [[ANYPTR]] = !{!"any pointer", {{.*}}}
