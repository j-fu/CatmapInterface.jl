"""
    ideal_gas(energies::Dict{String, Tval}, catmap_params::CatmapParams) where Tval <: Real

Add thermodynamic correction terms for all gas species using the ideal gas approximation.
"""
function ideal_gas(energies::Dict{String, Tval}, catmap_params::CatmapParams) where Tval <: Real
    @local_unitfactors eV
    
    ideal_gas_params = py"ideal_gas_params"
    (; species_list, T) = catmap_params
    for (s, sp) in species_list
        if isa(sp, GasSpecies)
            (; species_name, frequencies) = sp
            try
                (symmetrynumber, geometry, spin) = ideal_gas_params[s]
                energies[s] += py"get_thermal_correction_ideal_gas"(T, frequencies, symmetrynumber, geometry, spin, species_name) * eV
            catch e
                if isa(e, KeyError)
                    throw(ArgumentError("$s has no specified ideal gas parameters"))
                else
                    throw(e)
                end
            end
        end
    end
end

"""
    harmonic_adsorbate(energies, catmap_params::CatmapParams)

Add thermodynamic correction terms for all adsorbed species using the harmonic adsorbate approximation.
"""
function harmonic_adsorbate(energies, catmap_params::CatmapParams)
    @local_unitfactors eV
    (; species_list, T) = catmap_params
    for (s, sp) in species_list
        if isa(sp, AdsorbateSpecies)
            (; frequencies) = sp
            energies[s] += py"get_thermal_correction_adsorbate"(T, frequencies) * eV
        end
    end
    for (s, sp) in species_list
        if isa(sp, TStateSpecies)
            (; between_species) = sp
            for bs in between_species
                if isa(species_list[bs], AdsorbateSpecies)
                    (; formation_energy) = species_list[bs]
                    thermo_correction = energies[bs] - formation_energy
                    energies[s] += 0.5 * thermo_correction
                end
            end
        end
    end
end

"""
    hbond_surface_charge_density(energies, catmap_params::CatmapParams, σ, ϕ_we, ϕ, local_pH)

Add electrochemical correction terms for all influenced species using ...
"""
function hbond_surface_charge_density(energies, catmap_params::CatmapParams, σ, ϕ_we, ϕ, local_pH)
    @local_unitfactors eV
    hbond_dict = py"hbond_dict"
    (; species_list, T, Upzc, potential_reference_scale) = catmap_params
    # simple_electrochem_corrections
    if haskey(energies, "ele_g")
        energies["ele_g"] += -(ϕ_we - ϕ) * eV
    end
    for (s, sp) in species_list
        if isa(sp, TStateSpecies)
            (; β) = sp
            energies[s] += (-(ϕ_we - ϕ) + β * (ϕ_we - ϕ - Upzc)) * eV
        end
    end
    # hbond_electrochemical
    for (s, sp) in species_list
        if isa(sp, AdsorbateSpecies)
            (; species_name) = sp
            if haskey(hbond_dict, species_name)
                energies[s] += hbond_dict[species_name] * eV
            end
        end
    end
    # hbond_surface_charge_density
    for (s, sp) in species_list
        if (isa(sp, AdsorbateSpecies) || isa(sp, TStateSpecies))
            (; a, b) = sp.sigma_params
            energies[s] += (a * σ + b * σ^2) * eV
        end
    end
    # pH_correction
    if haskey(species_list, "H_g") || haskey(species_list, "OH_g")
        G_H2 = energies["H2_g"]
        if potential_reference_scale == "SHE"
            G_H = G_H2 * 0.5 - (0.0592 * local_pH / 298.14 * T) * eV
        elseif potential_reference_scale == "RHE"
            G_H = G_H2 * 0.5
        end
        G_H2O = energies["H2O_g"]
        G_OH = G_H2O - G_H
        if haskey(species_list, "H_g")
            energies["H_g"] += G_H
        end
        if haskey(species_list, "OH_g")
            energies["OH_g"] += G_OH
        end
    end
end