using JLD2;
using IterativeSolvers;
include("mesh.jl");
include("tree.jl");
include("utils.jl");
include("linsolve.jl");
include("amperesolve.jl");
include("amperesolve_delta.jl");
include("computeFields.jl");

xmax = 20.0;
xmin = -20.0;
ymax = 20.0;
ymin = -20.0;
zmax = 20.0;
zmin = -20.0;
Lx_max = 10.0;
Lx_min = -10.0;
Ly_max = 10.0;
Ly_min = -10.0;
Lz1 = -4.0;
Lz2 = 0.0;
Lz3 = 4.0;
Nc = 3;

Sx_max = 4.0;
Sx_min = -4.0;
Sy_max = 4.0;
Sy_min = -4.0;
Sz_max = 4.0;
Sz_min = -4.0;

Nx = 21;           # number of vertices along x
Ny = 21;           # number of vertices along y
Nz = 21;           # number of vertices along z
ne_x = Nx - 1;    # number of x-edge on each row
ne_y = Ny - 1;    # number of y-edge on each column
ne_z = Nz - 1;    # number of z-edge on each column
Ne_x = ne_x * Ny * Nz;   # total number of x-edges
Ne_y = ne_y * Nx * Nz;   # total number of y-edges
Ne_z = ne_z * Nx * Ny;   # total number of z-edges
Ne = Ne_x + Ne_y + Ne_z; # total number of edges
Nv = Nx * Ny * Nz;       # total number of vertices
Nbranch = Nx * ne_y + ne_x + Ne_z;
lx = (xmax - xmin) / ne_x;
ly = (ymax - ymin) / ne_y;
lz = (zmax - zmin) / ne_z;
Nv_xyplane = Nx * Ny;
Nex_xyplane = ne_x * Ny;
Ney_xyplane = ne_y * Nx;
Ne_xyplane = Nex_xyplane + Ney_xyplane; # doesn't inlcude z edges

# edge info for the current loop
ne_x_loop = Int((Lx_max - Lx_min) / lx);
ne_y_loop = Int((Ly_max - Ly_min) / ly);
ne_per_ring = 2 * (ne_x_loop + ne_y_loop);
necurrent = Nc * ne_per_ring;

# edge info for the superconducting piece
ne_scx = Int((Sx_max - Sx_min) / lx);
ne_scy = Int((Sy_max - Sy_min) / ly);
ne_scz = Int((Sz_max - Sz_min) / lz);
Ne_scx = ne_scx * (ne_scy + 1) * (ne_scz + 1);
Ne_scy = (ne_scx + 1) * ne_scy * (ne_scz + 1);
Ne_scz = (ne_scx + 1) * (ne_scy + 1) * ne_scz;
Ne_sc = Ne_scx + Ne_scy + Ne_scz;
Ne_scx_xyplane = ne_scx * (ne_scy + 1);
Ne_scy_xyplane = ne_scy * (ne_scx + 1);
Ne_scz_xyplane = (ne_scx + 1) * (ne_scy + 1);

# edge info for air 
ne_airx_seg = Int((Sx_min - xmin) / lx);
ne_airy_seg = Int((Sy_min - ymin) / ly);
ne_airz_seg = Int((Sz_min - zmin) / lz);

# Some constants
fo = 1e9;                # 1GHz
to = 1 / fo;               # 
lo = 1e-6;               # 1 um
Qo = -2 * 1.60217663e-19;   # 2*electron charge
mo = 2 * 9.1093837015e-31; # 2*electron mass
Phi_o = 2.067833848e-15;    # magnetic flux quantum
eps_o = 8.8541878128e-12;   # vacuum permitivity
mu_o = 1.25663706212e-6;   # vacuum magnetic permeability
lambda_o = 1e-6;               # 1 um
C = 299792458; # speed of light

# Input values
Q = 1.0 * 1e1; # this is actually Q/lo, since below we define A2 and J1 without lo in the denominator
freq = 3e4;
Period = 1 / freq; # 
Omega = 2 * pi * freq;
J = 1.0;
Nstep = 100;
simulatetime = Period;
dt = simulatetime / (Nstep - 1);
nperiod = 2;
eps_air = 1.0;
eps_sc = 1.0;
mu_air = 1.0;
mu_sc = 1.0;
lambda = 2.0; # in micrometer
max_iter = 15;
conv_tol = 0.05;


# scaling for Ampere's and Gauss's equation
A1 = to^2 / (mu_o * eps_o * lo^2);
#A2       = (to*Qo)/(eps_o*lo*Phi_o);
A2 = (to * Qo) / (eps_o * Phi_o); # instead of having lo in denominator, absorb it into Q above
G1 = to^2 / (eps_o * mu_o * lambda_o^2);
G2 = Qo * Phi_o * to / (mo * lo^2);
S1 = A1;
S2 = to^2 / (mu_o * eps_o * lambda_o^2);
S3 = (Qo * to * Phi_o) / (mo * lo^2);
S4 = (to * Qo * Phi_o) / (mo * lo^2);
J1 = to * Qo / (eps_o * Phi_o); # instead of having lo in denominator, absorb it into Q above
#J1       = to*Qo/(eps_o*Phi_o*lo);
Is1 = (Phi_o * to) / (mu_o * Qo * lo);
Is2 = (eps_o * Phi_o^2) / (mo * lo);
rho1 = mu_o * eps_o * Qo * Phi_o / (mo * to);


# define locations of the current edges
currentloc = zeros(2, 3, necurrent);
# 1st RING
for m = 1:ne_x_loop
    xc = Lx_min + (m - 1) * lx
    currentloc[:, :, m] = [xc Ly_min Lz1; xc+lx Ly_min Lz1] # currents live on the edges
end
for m = 1:ne_x_loop
    xc = Lx_min + (m - 1) * lx
    currentloc[:, :, ne_x_loop+m] = [xc Ly_max Lz1; xc+lx Ly_max Lz1] # currents live on the edges
end
for m = 1:ne_y_loop
    yc = Ly_min + (m - 1) * ly
    currentloc[:, :, 2*ne_x_loop+m] = [Lx_min yc Lz1; Lx_min yc+ly Lz1] # currents live on the edges
end
for m = 1:ne_y_loop
    yc = Ly_min + (m - 1) * ly
    currentloc[:, :, 2*ne_x_loop+ne_y_loop+m] = [Lx_max yc Lz1; Lx_max yc+ly Lz1] # currents live on the edges
end
# 2nd RING
for m = 1:ne_x_loop
    xc = Lx_min + (m - 1) * lx
    currentloc[:, :, ne_per_ring+m] = [xc Ly_min Lz2; xc+lx Ly_min Lz2] # currents live on the edges
end
for m = 1:ne_x_loop
    xc = Lx_min + (m - 1) * lx
    currentloc[:, :, ne_per_ring+ne_x_loop+m] = [xc Ly_max Lz2; xc+lx Ly_max Lz2] # currents live on the edges
end
for m = 1:ne_y_loop
    yc = Ly_min + (m - 1) * ly
    currentloc[:, :, ne_per_ring+2*ne_x_loop+m] = [Lx_min yc Lz2; Lx_min yc+ly Lz2] # currents live on the edges
end
for m = 1:ne_y_loop
    yc = Ly_min + (m - 1) * ly
    currentloc[:, :, ne_per_ring+2*ne_x_loop+ne_y_loop+m] = [Lx_max yc Lz2; Lx_max yc+ly Lz2] # currents live on the edges
end
# 3rd ring
for m = 1:ne_x_loop
    xc = Lx_min + (m - 1) * lx
    currentloc[:, :, 2*ne_per_ring+m] = [xc Ly_min Lz3; xc+lx Ly_min Lz3] # currents live on the edges
end
for m = 1:ne_x_loop
    xc = Lx_min + (m - 1) * lx
    currentloc[:, :, 2*ne_per_ring+ne_x_loop+m] = [xc Ly_max Lz3; xc+lx Ly_max Lz3] # currents live on the edges
end
for m = 1:ne_y_loop
    yc = Ly_min + (m - 1) * ly
    currentloc[:, :, 2*ne_per_ring+2*ne_x_loop+m] = [Lx_min yc Lz3; Lx_min yc+ly Lz3] # currents live on the edges
end
for m = 1:ne_y_loop
    yc = Ly_min + (m - 1) * ly
    currentloc[:, :, 2*ne_per_ring+2*ne_x_loop+ne_y_loop+m] = [Lx_max yc Lz3; Lx_max yc+ly Lz3] # currents live on the edges
end

# assign current values
currentamp = J * ones(necurrent);
# 1st ring
currentamp[1:ne_x_loop] = J * ones(ne_x_loop);
currentamp[ne_x_loop+1:2*ne_x_loop] = -1.0 * J * ones(ne_x_loop);
currentamp[2*ne_x_loop+1:2*ne_x_loop+ne_y_loop] = -1.0 * J * ones(ne_y_loop);
currentamp[2*ne_x_loop+ne_y_loop+1:ne_per_ring] = J * ones(ne_y_loop);
# 2nd ring
currentamp[ne_per_ring+1:ne_per_ring+ne_x_loop] = J * ones(ne_x_loop);
currentamp[ne_per_ring+ne_x_loop+1:ne_per_ring+2*ne_x_loop] = -1.0 * J * ones(ne_x_loop);
currentamp[ne_per_ring+2*ne_x_loop+1:ne_per_ring+2*ne_x_loop+ne_y_loop] = -1.0 * J * ones(ne_y_loop);
currentamp[ne_per_ring+2*ne_x_loop+ne_y_loop+1:2*ne_per_ring] = J * ones(ne_y_loop);
# 3rd ring
currentamp[2*ne_per_ring+1:2*ne_per_ring+ne_x_loop] = J * ones(ne_x_loop);
currentamp[2*ne_per_ring+ne_x_loop+1:2*ne_per_ring+2*ne_x_loop] = -1.0 * J * ones(ne_x_loop);
currentamp[2*ne_per_ring+2*ne_x_loop+1:2*ne_per_ring+2*ne_x_loop+ne_y_loop] = -1.0 * J * ones(ne_y_loop);
currentamp[2*ne_per_ring+2*ne_x_loop+ne_y_loop+1:3*ne_per_ring] = J * ones(ne_y_loop);

e, v = Mesh3Dcube(xmin, ymin, zmin, Nx, ne_x, Ne_x, Ne_y, Ne_z, Ne, Nv, lx, ly, lz, Nv_xyplane, Nex_xyplane, Ney_xyplane);
vbound, xtol, ytol, ztol = vboundary3D(v, xmax, xmin, ymax, ymin, zmax, zmin, Nv, Nx, Ny, Nv_xyplane);
v2exmap, v2eymap, v2ezmap = vemap3D(v, Nx, Nv, ne_x, Ne_x, Ne_y, xtol, ytol, ztol, xmin, xmax, ymin, ymax, zmin, zmax, Nex_xyplane, Ney_xyplane, Nv_xyplane);
e_sc = regionsort3D(Nx, ne_x, Ne_x, Ne_y, ne_scx, Ne_scx, Ne_scy, Ne_scz, Ne_sc, Ne_scx_xyplane, Ne_scy_xyplane, Ne_scz_xyplane, Nv_xyplane, Nex_xyplane, Ney_xyplane, ne_airx_seg, ne_airy_seg, ne_airz_seg);
ebound, _ = eboundary3D(vbound, e, ne_x, ne_y, ne_z, Ne, Nx, Ny, Nz, Ne_x, Ne_y, Nex_xyplane, Ney_xyplane);
invLambda2 = materials(Ne, e_sc, lambda);

tree = stree3D(ne_x, Nbranch, Ney_xyplane, Ne_x, Ne_y, Ne_z);

## solve for phi
ecurrent = current3D(v, currentloc, currentamp, xtol, ytol, ztol, Nv, Nx, Ne, e);
# solve for phi_p
HMat = SteadyState_HMat_3D(Is1, Ne, ne_x, Nx, Ne_x, Ne_y, ebound, lx, ly, lz, invLambda2, Nex_xyplane, Ney_xyplane, Nv_xyplane);
Kcol = SteadyState_Kcol(ecurrent, lx, ly, lz);
z = reducedPhiMat3D(Ne, ne_x, ne_y, ne_z, Ne_x, Ne_y, Nx, Ny, Nz, Nex_xyplane, Ney_xyplane, Nv_xyplane);

RMat = z' * HMat * z;
Kcol_reduced = z' * Kcol;
HMat = nothing;
Kcol = nothing;
reltol = 1e-3;
phip_ss_x, phip_ss_y, phip_ss_z, history = linsolve_ssPhi3D_gmres(RMat, z, Kcol_reduced, ebound, Ne_x, Is1, invLambda2, J, ne_x, reltol)

Ax_ss = phip_ss_x ./ lx;
Ay_ss = phip_ss_y ./ ly;
Az_ss = phip_ss_z ./ lz;
A_ss = [Ax_ss; Ay_ss; Az_ss];

# reshape to grids for 2d plots
Ax_ss_grid = reshape(Ax_ss, ne_x, Ny, Nz);
Ay_ss_grid = reshape(Ay_ss, Nx, ne_y, Nz);
Az_ss_grid = reshape(Az_ss, Nx, Ny, ne_z);
Bx, By, Bz = computeBfield3D(phip_ss_x, phip_ss_y, phip_ss_z, Nx, Ny, Nz, ne_x, ne_y, ne_z, lx, ly, lz, Nex_xyplane, Ney_xyplane, Nv_xyplane);

@save "SimulationData3.jld2" Ax_ss Ay_ss Az_ss Ax_ss_grid Ay_ss_grid Az_ss_grid Bx By Bz history