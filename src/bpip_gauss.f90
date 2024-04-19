program bpip_gauss
implicit none
!OBJETCS/TYPES ----------------------------------------------------------------
type tier
  integer :: id
  double precision,allocatable :: xy(:,:)                                      !x-y coordinates     (from INP, NO CAMBIA)
  real :: h,z0                                                                 !height,base hgt     (from INP, NO CAMBIA)
  !projected:
  real,allocatable :: xy2(:,:)                                                 !projected coords    (changes for each wdir)
  real :: xmin,xmax,ymin,ymax                                                  !boundaries          (changes for each wdir)
  real :: hgt=0,wid=0,len=0.0                                                  !height,width,length (changes for each wdir)
  real :: L=0.0                                                                !L: min{ wid , hgt } (changes for each wdir)
  real :: gsh=0.0, xbadj=0.0, ybadj=0.0                                        !GEP values          (changes for each stack y wdir)
endtype

type building
  character(8)           :: nombre                                             !name
  real                   :: z0                                                 !base height
  type(tier),allocatable :: t(:)                                               !tier
endtype

type stack
  integer          :: id
  character(8)     :: nombre
  real             :: z0, h
  real             :: xy(2), xy2(2)                                            !stack coords
  integer          :: whichRoof=0                                              !id to the roof where this stack is placed
  character(8)     :: roofName =""                                             !building name of where stack is placed
  logical          :: isOnRoof =.false.                                        !boolean flag that states if stack is over roof
endtype

type outTable  !output table
  character(8) :: stkName
  real         :: tabla(36,6)=0.0                                              !36 windirs, 6vars: wdir,hgt,wid,len,xbadj,ybadj
endtype

type stkTable  !stacks table
  character(8) :: stkName
  real         :: stkHeight, BaseElevDiff=-99.99, GEPEQN1=0.0, GEPSHV=65.0
endtype

!VARIABLES----------------------------------------------------------------------
!global params:
double precision, parameter :: pi=3.141593 !3.141592653589793_8
double precision, parameter :: deg2rad=pi/180.0
character(24),    parameter ::   inputFileName="BPIP.INP"
character(24),    parameter ::  outputFileName="bpip.out"
character(24),    parameter :: summaryFileName="bpip.sum"
!setup params
character (len=10) :: SWTN  ='P ', UNITS ="METERS    ",UTMP  ="UTMN"!SWTN UNITS !UTMP
real :: FCONV = 1.00, PNORTH=0.00                                   !PNORTH !FCONV
!indices:
integer :: i,j,k,d,i1,i2!,dd
!work variables:
character(78)               :: title                                           !title of the run
TYPE(building), allocatable :: B(:)                                            !array of buildings
TYPE(stack), allocatable    :: S(:)                                            !array of stacks
type(tier)                  :: fT,mT                                           !"current" or "focal" Tier and "max. GSH" tier
type(stack)                 :: Si                                              !"current" Stack
double precision            :: wdir                                            !direccion del viento
logical                     :: SIZ!,ROOF                                       !struc. influence zone boolean flag
real                        :: maxGSH,refWID!tmp                               !max GSH and WID encountred (for given stack and wdir)
integer                     :: mxtrs, gtnum                                   !max tier number found in input file
real, allocatable   :: DISTMN(:,:),DISTMNS(:,:)                                !distance Matrices: tier-tier, tier-stack 
! vars used for combine tiers
type(tier)          :: cT,T1,T2                                                !"combined", "sub-group" and "merge-candidate" Tier
integer,allocatable :: TLIST(:,:)!TLIST2(:,:)                                  !list of combinable (w/focal) tiers indices
integer,allocatable :: TLIST2(:)                                               !list of combined tiers ids
integer             :: TNUM,TNUM2                                              !TNUM= # of combinable tiers, TNUM2=# of actual combined tiers.
real                :: min_tier_dist                                           !min distance between stack and combined tiers
!out tables:
type(outTable), allocatable :: oTable(:)                                       !output table
type(stkTable), allocatable :: sTable(:)                                       !stack  table
!INPUT--------------------------------------------------------------------------
call readINP(inputFileName,B,S,title,mxtrs)                                    !read file & store data in B & S

allocate(oTable(size(S)))                                                      !allocatar tabla de salida
allocate(sTable(size(S)))                                                      !allocatar tabla de stacks
allocate(DISTMNS(size(B)*mxtrs,size(S)))     ; DISTMNS=0.0 
allocate(DISTMN(size(B)*mxtrs,size(B)*mxtrs)); DISTMN=0.0 
allocate( TLIST(size(B)*mxtrs, 2 ))          ;  TLIST=0    
allocate(TLIST2(size(B)*mxtrs))              ; TLIST2=0    
!MAIN---------------------------------------------------------------------------

!Calculate things that have "rotational invariance":
call check_which_stack_over_roof(S,B)                                          !check which stacks are placed over a roof.
call calc_dist_stacks_tiers(S,B,DISTMNS)                                       !calc min distance between stacks and tiers.
call calc_dist_tiers(B,DISTMN)                                                 !calc min distance between structures.

!if ( mod(int(pnorth),360) /= 0 ) call rotate_coordinates(B,S,sngl(-pnorth*deg2rad)) 
!call writeSUM1(summaryFileName,S,B,title)                                     !write 1st part of summary file.

DO d=1,36                                                                      !for each wdir (c/10 deg)
   
   wdir=d*10.0*deg2rad - pnorth*deg2rad                                        !get wdir [rad] 
   print '("      Wind flow passing", I4," degree direction.")', d*10 

   call rotate_coordinates(B,S,sngl(wdir))                                           !rotate coordinates (T%xy S%xy -> T%xy2 S%xy2)

   DO i=1,size(S)                                                              !for each stack
     maxGSH=0.0; refWID=0.0
     Si=S(i)
     gtnum=0 !# of tiers affecting stack
     !Single tiers structs   ---------------------------------------------------
     DO j=1,size(B)                                                            !for each building
        DO k=1,size(B(j)%T)                                                    !for each tier

           fT=B(j)%T(k)                                                        !create "focal" tier

           !check if stack is inside SIZ
           SIZ=           Si%xy2(1) .GE. (fT%xmin - 0.5*fT%L)  
           SIZ=SIZ .AND. (Si%xy2(1) .LE. (fT%xmax + 0.5*fT%L) )
           SIZ=SIZ .AND. (Si%xy2(2) .GE. (fT%ymin - 2.0*fT%L) )
           !SIZ=SIZ .AND. (y_stack .LE. (T%ymax + 5.0*T%L) )     !old
           SIZ=SIZ .AND. DISTMNS(fT%id,i) <= 5*fT%L
           if ( SIZ ) then                                                     
              gtnum=gtnum+1

              fT%gsh   = fT%z0 + fT%hgt - Si%z0 + 1.5*fT%L                    !GHS   [ Equation 1 (GEP, page 6) ]
              fT%ybadj = Si%xy2(1) - (fT%xmin + fT%wid * 0.5)                 !YBADJ = XPSTK - (XMIN(C) + TW*0.5)
              fT%xbadj = fT%ymin - Si%xy2(2)                                  !XBADJ = YMIN(C) - YPSTK             

              if ( fT%gsh > maxGSH .or. (fT%gsh == maxGSH .and. fT%wid < refWid) ) then !check if this tier has > GHS than previous ones
                 maxGSH=fT%gsh                                                 !set new ref GSH value
                 refWID=fT%wid                                                 !store its WID

                 mT=fT                                                         !set fT as the max GSH Tier
              end if
           endif
        END DO!tiers
     END DO!buildings

     !"COMBINED TIERS" ---------------------------------------------------------
     DO j=1,size(B)                                                            !
        DO k=1,size(B(j)%T)                                                    !for each focal tier

           fT=B(j)%T(k)                                                        !create "focal" tier
           
           call ListCombinableTiers(fT, B, DISTMN,TLIST,TNUM)                  !list combinable tiers and distances

           if ( TNUM > 0 ) then
             do i1=1,TNUM                                                      !on each combinable tier
                T1=B( TLIST(i1,1))%T( TLIST(i1,2) )                            !create "subgrup" tier "T1"

                if ( T1%hgt < fT%hgt .or. T1%id == fT%id ) then                !common hgt should be < focal tier hgt
                   cT     = fT                                                 !init. common ("combined") tier "cT"
                   cT%hgt = T1%hgt                                             !use T1_hgt as "common subgroup height"
                   cT%L   = min(cT%hgt, cT%wid)                                !update L

                   TNUM2=0                                                     !reset counter of combined tiers (tnum2) to 0
                   TLIST2=0                                                    !reset counter of combined tiers (tnum2) to 0
                   do i2=1,TNUM                                                !on each combinable candidate tier
                      T2=B(TLIST(i2,1))%T(TLIST(i2,2))                         !create candidate tier "T2"
                      T2%L=min(cT%hgt, T2%wid) !line 1213 de bpip orig use T2-L=min(T1hgt,T2wid)
                      if ( T2%hgt >= cT%hgt .and. T2%id /= cT%id ) then        !if T2_hgt >= common hgt, and is not cT
                         if ( DISTMN(cT%Id,T2%id) < max(T2%L, cT%L)) then      !if dist T2-fT is less than the maxL

                            !call combineTiers(cT,T2)                           !combine common Tier w/ T2 ! (update boundaries)
                            cT%xmin=min(cT%xmin, T2%xmin) 
                            cT%xmax=max(cT%xmax, T2%xmax)
                            cT%ymin=min(cT%ymin, T2%ymin)
                            cT%ymax=max(cT%ymax, T2%ymax)

                            TNUM2=TNUM2+1                                      !increment counter of combined tiers (tnum2)
                            TLIST2(TNUM2)=T2%id
                        endif
                      endif  
                   enddo                                                       !
                                                                               !Once all tiers has been combined w/tC
                   if ( TNUM2 > 0 ) then                                       !if there was at least 1 combined tier

                      cT%wid = cT%xmax - cT%xmin                               !update width
                      cT%len = cT%ymax - cT%ymin                               !update length
                      cT%L   = min(cT%hgt, cT%wid)                             !update "L"

                      min_tier_dist=minval(DISTMNS([fT%id,TLIST2(:TNUM2)],i))
                      !
                      !Here I need to define the Gap Filling Structure (GFS) polygon
                      !and use it to determine if SIZ-L5 distance stack-GFS is satisfied
                      !(could be solved using a "CONVEX HULL" algorithm, for example: Graham Scan Algorithm )
                      !

                      SIZ=          Si%xy2(1) .GE. cT%xmin-0.5*cT%L          !this is how SIZ is defined for comb Tiers
                      SIZ=SIZ .AND. Si%xy2(1) .LE. cT%xmax+0.5*cT%L          !Struc Influence Zone (SIZ)
                      SIZ=SIZ .AND. Si%xy2(2) .GE. cT%ymin-2.0*cT%L  
                      SIZ=SIZ .AND. min_tier_dist <= cT%L*5.0                !any of tiers combined is closer than cT%L*5.0 from stack

                      if ( SIZ ) then 

                         cT%gsh   = cT%z0 + cT%hgt - Si%z0 + 1.5*cT%L        !GSH    [ Equation 1 (GEP, page 6) ]
                         cT%ybadj = Si%xy2(1) - (cT%xmin + cT%wid * 0.5)     !YBADJ = XPSTK - (XMIN(C) + TW*0.5 )
                         cT%xbadj = cT%ymin - Si%xy2(2)                      !XBADJ = YMIN(C) - YPSTK

                         if ( cT%gsh > maxGSH .OR. ( maxGSH == cT%gsh .AND. cT%wid < refWID ) ) then 
                            maxGSH=cT%gsh
                            refWID=cT%wid
                            mT=cT
                         end if
                      endif
                   endif!TNUM2>0
                endif!T1%hgt < fT%hgt
             enddo!T1
           endif!TNUM>0
        END DO!tiers
     END DO!buildings
     
     !Add results to Out-Table/Stk-Table
     oTable(i)%stkName  = Si%nombre
     sTable(i)%stkName  = Si%nombre
     sTable(i)%stkHeight= Si%h
     if ( maxGSH /= 0.0 ) then    !if ( any_tier_affects_stack_at_this_wdir ) then
        oTable(i)%tabla(d,1:6)=[ sngl(wdir),mT%hgt,mT%wid,mT%len,mT%xbadj,mT%ybadj ] 
        if ( maxGSH > sTable(i)%GEPEQN1 ) then
           sTable(i)%BaseElevDiff = Si%z0 - mT%z0
           sTable(i)%GEPEQN1      = mT%gsh 
           sTable(i)%GEPSHV       = max(65.0, mT%gsh)
        endif
     !else   !no tier affects this stack at this wdir
     !   print '("           No tier affects this stack at this wdir. (",A10,")")',S(i)%nombre
     endif

   END DO!stacks
END DO!wdir

!OUTPUT:-----------------------------------------------------------------------
call writeOUT(oTable,sTable,title,outputFileName)

WRITE(*,'(/,A,/)') ' END OF BPIP RUN.'
contains
!GEOMETRY   ********************************************************************
subroutine rotate_coordinates(B,S,wdir) !Calc "new" (rotated) coordinates: xy --> xy2
    implicit none
    type(building),intent(inout) :: B(:)
    type(stack), intent(inout)   :: S(:)
    real,             intent(in) :: wdir  !original
    double precision :: D(2,2)   !usan distinta precision para stacks y buildings :/
    real             :: R(2,2)   !usan distinta precision para stacks y buildings :/
    integer :: i,j,k
    !matriz de rotación:       
    D(1,1)=dcos(dble(wdir)); D(1,2)=-dsin(dble(wdir)) !original
    D(2,1)=-D(1,2)   ; D(2,2)= D(1,1) 
    R(1,1)=cos(wdir) ; R(1,2)=-sin(wdir);
    R(2,1)=-R(1,2)   ; R(2,2)= R(1,1)

    !stack
    do i=1,size(S)
       S(i)%xy2=matmul(R,S(i)%xy)                                   !projected stack coordinates
    enddo
    !buildings
    do i=1,size(B)
       do j=1,size(B(i)%T)
           do k=1,size(B(i)%T(j)%xy(:,1))
              B(i)%T(j)%xy2(k,:)=sngl(matmul(D,B(i)%T(j)%xy(k,:)) ) !projected tiers coordinates
           enddo
           call calcTierProyectedValues(B(i)%T(j) )                 ! calc tier: xmin,xmax,ymin,ymax
       enddo
    enddo
end subroutine

real function DisLin2Point (X0, Y0, X1, Y1, XP, YP)                            !REPLACE of original "DISLIN" procedure
   !computes min distance between side/line defined by (v0,v1), and point (vp).
   implicit none
   real, intent(in)    :: x0,x1,y0,y1,xp,yp
   real, dimension(2)  :: v,p,d                                                !side (v), point (p), and v-p vector (d)
   real                :: mod2v,v_dot_p,dist                                   !length of v, dot_product(v,p)             
   v=[x1-x0, y1-y0] !v1-v0                                                     ! take vectors to same origin
   p=[xp-x0, yp-y0] !vp-v0                                                     ! take vectors to same origin
   mod2v = sqrt(dot_product(v,v))
   !proj_of_p_on_v=dot_product(v,p)/mod2v !proyeccion de p en v
   v_dot_p=dot_product(v,p) 

   if ( v_dot_p > mod2v**2 .or. v_dot_p < 0.0 .or. mod2v == 0.0 ) then
       d=v-p                                                                   !diference vector
       dist=sqrt(dot_product(d,d))                                             !distance between the "tip" of the vectors
   else 
       dist=abs(v(1)*p(2)-v(2)*p(1))/mod2v                                     !distance parametric line to point:  |v x p| / |v|
   end if
   DISLIN2POINT = dist
end function

real function minDist(xy1,xy2)            
   !min distance between two polygons
   real           ,intent(in) :: xy1(:,:), xy2(:,:)
   integer :: i,j,k,n,m
   m=size(xy1(:,1))
   n=size(xy2(:,1))
   minDist=1e20
   do i=1,n
     do j=1,m
       k=mod(j,m)+1
       minDist=min(minDist,dislin2point( xy1(j,1),xy1(j,2),  xy1(k,1),xy1(k,2), xy2(i,1), xy2(i,2)) )  !new! (faster)
     enddo
   enddo
end function

!logical function point_is_in_poly(point,poly)    result(inTier) 
logical function isInsideTier(S,T)    result(inTier) 
    !idea: if point inside poly, then sum of angles from p to consecutive corners (sides) must be == 2*pi
    implicit none
    !real  :: point(:,:),poly(:,:)
    type(stack), intent(in) :: S
    type(tier), intent(in)  :: T
    double precision:: angle_sum=0.0,angle=0.0,signo=1.0,v1_dot_v1,v2_dot_v2
    double precision:: v1(2), v2(2), p(2)
    integer :: i,j,n!,k
    p=dble(S%xy)
    n=size(T%xy(:,1))
    do i=1,n
        j=mod(i,n)+1
        v1=T%xy(i,:)-p
        v2=T%xy(j,:)-p
        v1_dot_v1=dot_product(v1,v1)
        v2_dot_v2=dot_product(v2,v2) 
        if (v1_dot_v1 == 0 .or. v2_dot_v2 == 0) then !this would means that v1 or v2 == p
           inTier=.true. ! or .false.? (something to discus)
           return
         else
           signo = dsign(signo,v1(1)*v2(2)-v1(2)*v2(1))      !sign of 3rd-component v1 x v2 (cross prod)
           angle = dacos( dot_product(v1,v2) / sqrt(v1_dot_v1*v2_dot_v2) )
           angle_sum = angle_sum + signo * angle
        end if
    enddo
    inTier=(ABS(2*pi - ABS(angle)) .LT. 1e-4) 
end function

!STACK IS OVER ROOF? ******************************************************************************
subroutine check_which_stack_over_roof(S,B)
    implicit none
    type(stack) ,intent(inout) :: S(:)
    type(building),intent(in)  :: B(:)        
    integer                    :: i,j,k
    print*, "Detect if a stack is on top of a roof"
    DO i=1,size(S)                                                             !for each stack
       DO j=1,size(B)                                                          !for each building
           DO k=1,size(B(j)%T)                                                 !for each tier
             !if ( point_is_in_poly(S(i)%xy, B(j)%T(k)%xy ) ) then
             if ( isInsideTier(S(i), B(j)%T(k)) ) then
                print '(A10,"=>",A10)',S(i)%nombre, B(j)%nombre
                S(i)%isOnRoof  = .true.
                S(i)%whichRoof = (I-1) * MXTRS + J ![j,k] 
                S(i)%roofName  = B(j)%nombre
                return!exit
             endif
          enddo
       enddo
    enddo
end subroutine

!BPIP PARAM CALCULATIONS **************************************************************************
subroutine calcTierProyectedValues(T) !Calculo de XMIN XMAX YMIN YMAX,WID,HGT,LEN,L
    implicit none
    type(tier),intent(inout)   :: T
    T%xmin= minval(T%xy2(:,1)) ; T%xmax=maxval(T%xy2(:,1)) 
    T%ymin= minval(T%xy2(:,2)) ; T%ymax=maxval(T%xy2(:,2)) 
    T%wid = T%xmax - T%xmin
    T%len = T%ymax - T%ymin
    T%hgt = T%h
    T%L   = min(T%wid, T%hgt)
end subroutine
!
subroutine calc_dist_stacks_tiers(S,B,Matrix)
   implicit none
   type(stack),intent(in)       :: S(:)        
   type(building),intent(in)    :: B(:)        
   real,          intent(inout) :: Matrix(:,:)
   integer :: i,j,k,idt
   print*, "Calculate min distance between tiers and stacks"
   do i=1,size(S)                                                              !on each stack
   do j=1,size(B)                                                              !on each building
   do k=1,size(B(j)%T)                                                         !on each tier
      idt= B(j)%T(k)%id                                                        !get tier id 
          if ( S(i)%whichRoof == B(j)%T(k)%id ) then
             Matrix(idt,i) = 0.0
          else
             Matrix(idt,i) = mindist(sngl(B(j)%T(k)%xy), reshape(sngl(S(i)%xy),[1,2]))  !store min distance between structures
          end if
   end do 
   end do 
   end do 
   !print '(25(F9.4))',Matrix !debug
end subroutine

subroutine calc_dist_tiers(B,Matrix)
   implicit none
   type(building),intent(in)    :: B(:)        
   real,          intent(inout) :: Matrix(:,:)
   integer :: i,j,n,ii,jj,id1,id2
   print*, "Calculate min distance between buildings"
   n=size(B)
   do i=1,n                         !on each building
   do j=1,size(B(i)%T)              !on each tier
      id1= (i-1)*mxtrs + j 
      do ii=1,n                      !on each other building
      do jj=1,size(B(ii)%T)          !on each other tier
          id2= (ii-1)*mxtrs + jj
          if ( id1 > id2 ) then
             Matrix(id1,id2) = mindist(sngl(B(i)%T(j)%xy), sngl(B(ii)%T(jj)%xy))!store min distance between structures
             Matrix(id2,id1) = Matrix(id1,id2)                                  !(symetry)
          end if
        end do 
        end do 
   end do 
   end do 
   !print '(6(F9.4))',Matrix !debug
end subroutine

!MERGE TIERS **************************************************************************************
subroutine ListCombinableTiers(T,B,DISTMN,TLIST,TNUM)
    implicit none
    type(tier)    ,intent(in)    :: T                                          !"focal" Tier
    type(building),intent(in)    :: B(:)        
    real          ,intent(in)    :: DISTMN(:,:)
    integer       ,intent(inout) :: TLIST(:,:)                                 !list of indices of combinable tiers
    integer       ,intent(inout) :: TNUM                                       !# of combinable tiers
    real                         :: dist, maxL
    integer                      :: i,j

     tnum=0
     tlist=0
     do i=1,size(B)                                                            !on each building
          do j=1,size(B(i)%T)                                                  !on each tier    
             dist = DISTMN(T%id, B(i)%T(j)%id)                                 !get dist
             maxL =    max(T%L , B(i)%T(j)%L )                                 !"If the GREATER of each pair of Ls is greater than the minimum distance
             if ( dist < maxL ) then                                           !if dist less than maxL tiers are "COMBINABLE"
                tnum=tnum+1
                tLIST(tnum,:)=[i,j]
             endif
          enddo
     enddo
end subroutine
!INPUT:  ******************************************************************************************
subroutine readINP(inp_file,B,S,title,mxtrs) 
        implicit none
        character(78),intent(inout) :: title
        integer      ,intent(inout) :: mxtrs
        character(24),intent(in) :: inp_file
        TYPE(building),allocatable, intent(inout) :: B(:)
        TYPE(stack),allocatable, intent(inout) :: S(:)
        integer :: nb,nt,nn,ns !# builds,# tiers # nodes,# stacks
        integer :: i,j,k

        WRITE(*,'(/,A,/)') ' READING INPUT DATA FROM FILE.'
        open(1,file=inp_file,action="READ")
          !HEADER: 
          read(1,*) title         !titulo
          read(1,*) SWTN          !run options 'P', 'NP', 'ST', 'LT'
          read(1,*) UNITS, FCONV  !units        & factor of correction
          read(1,*) UTMP , PNORTH !coord system & initial angle
          !BUILDINGS:
          read(1,*) nb                              !# buildings
          allocate(B(nb)) 
          do i=1,nb,1                               !read buildings and tiers
             read(1,*) B(i)%nombre,nt,B(i)%z0       !name ntiers z0
             B(i)%z0=B(i)%z0*FCONV                  !convert hgt units to meters
             mxtrs=max(mxtrs,nt)  
             allocate(B(i)%T(nt))
             do j=1,nt,1
                B(i)%T(j)%z0=B(i)%z0                !asign tier same base elev tha building
                read(1,*) nn, B(i)%T(j)%h !hgt  !nn hgt
                B(i)%T(j)%h=B(i)%T(j)%h*FCONV       !convert hgt units to meters
                allocate(B(i)%T(j)%xy(nn,2))
                allocate(B(i)%T(j)%xy2(nn,2))
                do k=1,nn,1
                   read(1,*) B(i)%T(j)%xy(k,1), B(i)%T(j)%xy(k,2)     !x y
                enddo
             enddo
          end do
          !STACKS:       
          read(1,*)ns  !#stacks
          allocate(S(ns)) 
          do i=1,ns,1 !read stacks
                  read(1,*) S(i)%nombre, S(i)%z0, S(i)%h, S(i)%xy(1), S(i)%xy(2)    !name z0 h x y
                  S(i)%id=i !stacks are indexed by order of aparence on input file
                  S(i)%z0=S(i)%z0*FCONV
          end do
        close(1)
        WRITE(*,'(/,A,/)') ' END OF READING INPUT DATA FROM FILE.'
        !----------------------------------------------------------------------
        ! INDEXING
        !Building Indexing:
        do i=1,size(B);do j=1,size(B(i)%T)                                             !indexing tiers
          B(i)%T(j)%id=(i-1) * mxtrs + j                                               !give each tier an absolute ID
        enddo; enddo;
        !Stacks Indexing: stacks are indexed while reading input file by the order of ocurrence
        !----------------------------------------------------------------------
end subroutine
!OUTPUT: ******************************************************************************************
subroutine writeOUT(oT,sT,title,outputFileName)
    implicit none
    integer ::i
    character(78),  intent(in) :: title
    type(outTable), intent(in) :: ot(:)
    type(stkTable), intent(in) :: st(:)
    character(24),intent(in) :: outputFileName

    open(12,file=outputFileName,action="WRITE")
        WRITE(12,'(1X,A78,/)') TITLE
        !DATE:
        call writeDATE(12)
        WRITE(12,'(1X,A78,/)') TITLE
        WRITE(12,*) '============================'
        WRITE(12,*) 'BPIP PROCESSING INFORMATION:'
        WRITE(12,*) '============================'
        !
        WRITE(12,"(/3X,'The ',A2,' flag has been set for preparing downwash',' related data',10X)")  SWTN   !'P '
        WRITE(12,"('          for a model run utilizing the PRIME algorithm.',/)"                 ) 
        WRITE(12,"(3X,'Inputs entered in ',A10,' will be converted to ','meters using ')"         )  UNITS  !"METERS    "
        WRITE(12,"(3X,' a conversion factor of',F10.4,'.  Output will be in meters.',/)"          )  FCONV  !1.00
        WRITE(12,"(3X,'UTMP is set to ',A4,'.  The input is assumed to be in',' a local')"        )  UTMP   !"UTMN"
        WRITE(12,"(3x,' X-Y coordinate system as opposed to a UTM',' coordinate system.')"        ) 
        WRITE(12,"(3x,' True North is in the positive Y',' direction.',/)")                                 ! 
        WRITE(12,"(3X,'Plant north is set to',F7.2,' degrees with respect to',' True North.  ',//)") PNORTH ! 0.00
        WRITE(12,'(1X,A78,///)') TITLE
        !STACK RESULTS
        WRITE(12,"(16X,'PRELIMINARY* GEP STACK HEIGHT RESULTS TABLE')")
        WRITE(12,"(13X,'            (Output Units: meters)',/)")
        WRITE(12,"(8X,'                    Stack-Building            Preliminary*')")
        WRITE(12,"(8X,' Stack    Stack     Base Elevation    GEP**   GEP Stack')")
        WRITE(12,"(8X,' Name     Height    Differences       EQN1    Height Value',//)")
        do i=1,size(sT,1)
           if ( st(i)%BaseElevDiff .EQ. -99.99 ) then
              !                                                   STKN(S),       SH(S),         GEP(S),    PV
              WRITE(12,'(8X, A8, F8.2, 10X, "N/A",5X,3(F8.2,5X))') st(i)%stkName, st(i)%stkHeight, st(i)%GEPEQN1, st(i)%GEPSHV 
           else
              !                                STKN(S),        SH(S),           DIF,                 GEP(S),       PV
              WRITE(12,'(8X, A8, 4(F8.2,5X))') st(i)%stkName, st(i)%stkHeight, st(i)%BaseElevDiff, st(i)%GEPEQN1, st(i)%GEPSHV
           end if
        end do
        WRITE(12,"(/,'   * Results are based on Determinants 1 & 2 on pages 1',' & 2 of the GEP')   ")
        WRITE(12,"( '     Technical Support Document.  Determinant',' 3 may be investigated for')  ")
        WRITE(12,"( '     additional stack height cred','it.  Final values result after')          ")
        WRITE(12,"( '     Determinant 3 has been ta','ken into consideration.')                    ")
        WRITE(12,"( '  ** Results were derived from Equation 1 on page 6 of GEP Tech','nical')     ")
        WRITE(12,"( '     Support Document.  Values have been adjusted for a','ny stack-building') ")
        WRITE(12,"( '     base elevation differences.',/)                                          ")
        WRITE(12,"( '     Note:  Criteria for determining stack heights for modeling',' emission') ")
        WRITE(12,"( '     limitations for a source can be found in Table 3.1 of the')              ")
        WRITE(12,"( '     GEP Technical Support Document.')                                        ")
        WRITE(12,"(/,/,/,/)")
        !DATE (AGAIN)
        call writeDATE(12)
        WRITE(12,'(//,1X,A78,/)') TITLE
        WRITE(12, *) ' BPIP output is in meters'

        !MAIN OUTPUT:
        do i=1,size(oT,1),1
            write(12,'(/)')
            !HGT
            write(12,'(5X,"SO BUILDHGT ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(1:6  ,2)
            write(12,'(5X,"SO BUILDHGT ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(7:12 ,2)
            write(12,'(5X,"SO BUILDHGT ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(13:18,2)
            write(12,'(5X,"SO BUILDHGT ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(19:24,2)
            write(12,'(5X,"SO BUILDHGT ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(25:30,2)
            write(12,'(5X,"SO BUILDHGT ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(31:36,2)
            !WID
            write(12,'(5X,"SO BUILDWID ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(1:6  ,3)
            write(12,'(5X,"SO BUILDWID ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(7:12 ,3)
            write(12,'(5X,"SO BUILDWID ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(13:18,3)
            write(12,'(5X,"SO BUILDWID ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(19:24,3)
            write(12,'(5X,"SO BUILDWID ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(25:30,3)
            write(12,'(5X,"SO BUILDWID ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(31:36,3)
            !LEN
            write(12,'(5X,"SO BUILDLEN ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(1:6  ,4)
            write(12,'(5X,"SO BUILDLEN ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(7:12 ,4)
            write(12,'(5X,"SO BUILDLEN ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(13:18,4)
            write(12,'(5X,"SO BUILDLEN ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(19:24,4)
            write(12,'(5X,"SO BUILDLEN ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(25:30,4)
            write(12,'(5X,"SO BUILDLEN ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(31:36,4)
            !XBADJ12
            write(12,'(5X,"SO XBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(1:6  ,5)
            write(12,'(5X,"SO XBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(7:12 ,5)
            write(12,'(5X,"SO XBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(13:18,5)
            write(12,'(5X,"SO XBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(19:24,5)
            write(12,'(5X,"SO XBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(25:30,5)
            write(12,'(5X,"SO XBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(31:36,5)
            !YBADJ12
            write(12,'(5X,"SO YBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(1:6  ,6)
            write(12,'(5X,"SO YBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(7:12 ,6)
            write(12,'(5X,"SO YBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(13:18,6)
            write(12,'(5X,"SO YBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(19:24,6)
            write(12,'(5X,"SO YBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(25:30,6)
            write(12,'(5X,"SO YBADJ    ",a8,6(f8.2))') oT(i)%stKName,oT(i)%tabla(31:36,6)
        end do
    close(12)!cierro bpip.out
end subroutine

subroutine writeDATE(iounit)
    implicit none
    integer, intent(in) :: iounit      
    integer :: date_time(8)
    integer :: iyr,imon,iday,ihr,imin,isec
    character(len=12) :: real_clock(3)
    CALL DATE_AND_TIME (REAL_CLOCK (1), REAL_CLOCK (2), REAL_CLOCK (3), DATE_TIME)
    IYR = DATE_TIME(1); IMON = DATE_TIME(2); IDAY = DATE_TIME(3)
    IHR = DATE_TIME(5); IMIN = DATE_TIME(6); ISEC = DATE_TIME(7)
    !header:
     WRITE (iounit,'(30X,"BPIP (Dated: 24241 )")')
     WRITE (iounit,'(1X, "DATE : ",I2,"/",I2,"/",I4)') IMON, IDAY, IYR
     WRITE (iounit,'(1X, "TIME : ",I2,":",I2,":",I2)') IHR, IMIN, ISEC
end subroutine

!!subroutine writeSUM1(fileName,S,B,title)
!!   implicit none
!!   integer :: i,j,k
!!   character(78) , intent(in) :: title
!!   type(stack)   , intent(in) :: S(:)
!!   type(building), intent(in) :: B(:)
!!   character(24),intent(in) :: FileName
!!
!!    open(14,file=FileName, action="WRITE")
!!      WRITE(14,'(1X,A78,/)') TITLE
!!      !DATE:
!!      call writeDATE(14)
!!      WRITE(14,'(1X,A78,/)') TITLE
!!      WRITE(14,*) "============================"
!!      WRITE(14,*) "BPIP PROCESSING INFORMATION:"
!!      WRITE(14,*) "============================"
!!      !Global options:
!!      WRITE(14,"(/3X,'The ',A2,' flag has been set for preparing downwash',' related data',10X)") SWTN
!!      WRITE(14,"('          for a model run utilizing the PRIME algorithm.',/)"                 )
!!      WRITE(14,"(3X,'Inputs entered in ',A10,' will be converted to ','meters using ')"         ) UNITS
!!      WRITE(14,"(3X,' a conversion factor of',F10.4,'.  Output will be in meters.',/)"          ) FCONV
!!      WRITE(14,"(3X,'UTMP is set to ',A4,'.  The input is assumed to be in',' a local')"        ) UTMP
!!      WRITE(14,"(3x,' X-Y coordinate system as opposed to a UTM',' coordinate system.')"        )
!!      WRITE(14,"(3x,' True North is in the positive Y',' direction.',/)")
!!      WRITE(14,'(3X,"Plant north is set to",F7.2," degrees with respect to"," True North.  ")'  ) PNORTH
!!      WRITE(14,'(//,1X,A78,///)'                                                                ) TITLE
!!      !
!!      WRITE(14,*) "=============="
!!      WRITE(14,*) "INPUT SUMMARY:"
!!      WRITE(14,*) "=============="
!!      WRITE(14, '(//,1X,"Number of buildings to be processed :",I4)') size(B) ! NB
!!      do i=1,size(B)
!!       WRITE(14,'(//1X,A8," has",I2," tier(s) with a base elevation of",F8.2," ",A10)') B(i)%nombre,size(B(i)%T),B(i)%z0,UNITS
!!         !TABLE:
!!         WRITE(14,'(" BUILDING  TIER  BLDG-TIER  TIER   NO. OF      CORNER   COORDINATES")')
!!         WRITE(14,'("   NAME   NUMBER   NUMBER  HEIGHT  CORNERS        X           Y"/)')
!!         do j=1,size(B(i)%T)
!!           WRITE(14,'(1X,A8,I5,5X,I4,4X,F6.2,I6)') B(i)%nombre, j, B(i)%T(j)%id, B(i)%T(j)%h, size(B(i)%T(j)%xy(:,1))
!!           do k=1, size(B(i)%T(j)%xy(:,1))
!!              WRITE(14,'(42X,2F12.2, 1X,"meters")') B(i)%T(j)%xy(k,1),B(i)%T(j)%xy(k,2)
!!              if (mod(int(pnorth),360) /= 0.0 ) then
!!                  WRITE(14,'(41X,"[",2F12.2,"] meters")') B(i)%T(j)%xy2(k,1),B(i)%T(j)%xy2(k,2)
!!              endif
!!           enddo
!!         enddo
!!      enddo
!!      !Stacks table:
!!      WRITE(14,'(/,1X,"Number of stacks to be processed :",I4,/)') size(S)
!!      WRITE(14, '("                    STACK            STACK   COORDINATES")')
!!      WRITE(14, '("  STACK NAME     BASE  HEIGHT          X           Y"/)')
!!      do i=1,size(S) 
!!         WRITE(14,'(2X, A8,3X, 2F8.2, 1X, A10)') S(i)%nombre, S(i)%z0, S(i)%h, UNITS
!!         WRITE(14,'(31X,2F12.2, " meters")') S(i)%xy(1),S(i)%xy(2)
!!         if (mod(int(pnorth),360) /= 0.0 ) then
!!             WRITE(14,'(30X,"[",2F12.2,"] meters")') S(i)%xy2(1),S(i)%xy2(2)
!!         endif
!!      enddo
!!      !stack on roof table
!!      if (ANY( S(:)%isOnRoof) ) then
!!          WRITE(14,*) ""
!!          WRITE(14,*) ""
!!          WRITE(14,*) " The following lists the stacks that have been identified"
!!          WRITE(14,*) "  as being atop the noted building-tiers."
!!          WRITE(14,*) "          STACK            BUILDING         TIER"
!!          do i=1,size(S) 
!!            if (s(i)%isOnRoof ) then
!!               WRITE(14,'(10X, A8, I4, 5X, A8, 2(1X, I5))') S(i)%nombre, S(i)%id, S(i)%roofName,S(i)%whichRoof, 1
!!            end if
!!          enddo
!!      else
!!         WRITE(14,*) ""
!!         WRITE(14,*) "   No stacks have been detected as being atop"
!!      endif
!!     close(14)
!!end subroutine
!!
!!subroutine writeSUM2(fileName,sT,S,B,title)
!!   implicit none
!!   integer :: i,j,k
!!   character(78) , intent(in) :: title
!!   type(stack)   , intent(in) :: S(:)
!!   type(building), intent(in) :: B(:)
!!   character(24),intent(in) :: FileName
!!
!!    open(14,FileName, action="WRITE", status="OLD")
!!
!!        WRITE(14,*)""
!!        WRITE(14,*)""
!!        WRITE(14,*)"                     Overall GEP Summary Table"
!!        WRITE(14,*)""
!!        WRITE(14,*)"                          (Units: meters)" 
!!        WRITE(14,*)""
!!        WRITE(14,*)""
!!
!!        !1021  FORMAT( 10X,'NOTE: The projected width values below are not always'
!!        !     *      ,/10X,'      the maximum width.  They are the minimum value,'
!!        !     *      ,/10X,'      valid for the stack in question, to derive the'
!!        !     *      ,/10X,'      maximum GEP stack height.'/)
!!        WRITE(14,'(" StkNo:", I3,"  Stk Name:", A8," Stk Ht:",F7.2," Prelim. GEP Stk.Ht:",F8.2,/11x," GEP:  BH:",F7.2,"  PBW:",F8.2, 11X, "  *Eqn1 Ht:",F8.2)'), i,st(i)%stkName, st(i)%stkHeight, st(i)%GEPEQN1, st(i)%GEPSHV! S(i)%nombre, S(i)%h,  st(i)%GEPEQN1, st(i)%GEPSHV !1022
!!        if (gtnum > 0) then       
!!          WRITE(14,'("  No. of Tiers affecting Stk:", I3,"  Direction occurred:", F8.2)'),GTNUM,d*10 !gdirs!GTNUM(S), GDIRS(S) !1023
!!          WRITE(14,'("   Bldg-Tier nos. contributing to GEP:", 10I4)') [mt%id, TLIST2(:TNUM2)]!(GTLIST(S,I), I = 1, GTNUM(S))
!!          WRITE(14,'(10X,"*adjusted for a Stack-Building elevation difference"," of",F8.2)') st(i)%BaseElevDiff  !1025
!!          WRITE(14,'(5X,  "Single tier MAX:  BH:",F7.2,"  PBW:",F7.2,"  PBL:",F7.2,"  *Wake Effect Ht:", F8.2/5X,"Relative Coordinates of Projected Width Mid-point: XADJ: ", F7.2,"  YADJ: ",F7.2/5X)'), mt%hgt,mt%wid,mt%len, mt%gsh,mt%xbadj,mt%ybadj !MXPBH(S,D), MXPBW(S,D),MXPBL(S,D), MHWE(S,D), MPADX(S,D),MPADY(S,D)  !1026
!!        else
!!           WRITE(14,*) "     No tiers affect this stack."
!!        endif
!!     close(14)
!!end subroutine
!!!
!!subroutine writeSUM3(fileName,S,T)
!!   implicit none
!!   integer :: i,j,k
!!   type(stack)   , intent(in) ::  S
!!   type(tier)    , intent(in) :: mT
!!   real          , intent(in) :: wdir
!!   character(24),intent(in) :: FileName
!!
!!    open(14,FileName, action="WRITE", status="OLD")
!!
!!        WRITE(14,*)""
!!        WRITE(14,*)""
!!        WRITE(14,*)"                     Summary By Direction Table"
!!        WRITE(14,*)""
!!        WRITE(14,*)"                          (Units:  meters)"
!!        WRITE(14,*)""
!!        WRITE(14,*)""
!!        WRITE(14,*)" Dominate stand alone tiers:"
!!
!!
!!        WRITE(14,'(/1X,"Drtcn: ", F6.2/)') wdir !604
!!        WRITE(14,'(" StkNo:", I3,"  Stk Name:", A8, 23X,"   Stack Ht:", F8.2)') S%id,S%nombre,S%h !2022
!!        WRITE(14,'(11X,"      GEP:  BH:",F7.2,"  PBW:",F7.2,"   *Equation 1 Ht:", F8.2)')                                                         !2027
!!        WRITE(14,'(3X,"Combined tier MAX:  BH:",F7.2,"  PBW:",F7.2,"  PBL:",F7.2,"  *WE Ht:", F8.2/5X,"Relative Coordinates of Projected Width Mid-point: XADJ: ",F7.2,"  YADJ: ",F7.2/5X)'),cT%hgt,ct%wid,ct%L,ct%gsh,mt%xbadj,mt%ybadj !2026
!!        WRITE(14, '("  No. of Tiers affecting Stk:", I3)')                     !2023  
!!        WRITE(14, '("   Bldg-Tier nos. contributing to MAX:", 10I4)')          !2024  
!!
!!     close(14)
!!end subroutine

end program
