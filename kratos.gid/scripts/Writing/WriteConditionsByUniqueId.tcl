
proc write::writeConditionsByUniqueId { baseUN ConditionMapVariableName {iter 0} {cond_id ""}} {
    set root [customlib::GetBaseRoot]

    set xp1 "[spdAux::getRoute $baseUN]/condition/group"
    set groupNodes [$root selectNodes $xp1]
    if {[llength $groupNodes] < 1} {
        set xp1 "[spdAux::getRoute $baseUN]/group"
        set groupNodes [$root selectNodes $xp1]
    }
    foreach groupNode $groupNodes {
        if {$cond_id eq ""} {set condid [[$groupNode parent] @n]} {set condid $cond_id}
        set groupid [get_domnode_attribute $groupNode n]
        set groupid [GetWriteGroupName $groupid]
        set iter [writeGroupNodeConditionByUniqueId $groupNode $condid $iter $ConditionMapVariableName]
    }
    return $iter
}


proc write::writeGroupNodeConditionByUniqueId {groupNode condid iter ConditionMapVariableName} {
    set groupid [get_domnode_attribute $groupNode n]
    set groupid [GetWriteGroupName $groupid]
    if {[$groupNode hasAttribute ov]} {set ov [$groupNode getAttribute ov]} {set ov [[$groupNode parent ] getAttribute ov]}
    set cond [::Model::getCondition $condid]
    if {$cond ne ""} {
        lassign [write::getEtype $ov $groupid] etype nnodes
        set kname [$cond getTopologyKratosName $etype $nnodes]
        if {$kname ne ""} {
            set iter [write::writeGroupConditionByUniqueId $groupid $kname $nnodes $iter $ConditionMapVariableName]
        } else {
            # If kname eq "" => no topology feature match, condition written as nodal
            if {[$cond hasTopologyFeatures]} {W "$groupid assigned to $condid - Selected invalid entity $ov with $nnodes nodes - Check Conditions.xml"}
        }
    } else {
        error "Could not find conditon named $condid"
    }
    return $iter
}


proc write::writeGroupConditionByUniqueId {groupid kname nnodes iter ConditionMap} {
    set obj [list ]

    # Print header
    set s [mdpaIndent]
    WriteString "${s}Begin Conditions $kname// GUI group identifier: $groupid"

    # Get the entities to print
    if {$nnodes == 1} {
        set formats [dict create $groupid "%10d \n"]
        set obj [GiD_EntitiesGroups get $groupid nodes]
    } else {
        set formats [write::GetFormatDict $groupid 0 $nnodes]
        set elems [GiD_EntitiesGroups get $groupid elements]
        set obj [GetListsOfNodes [GiD_WriteCalculationFile connectivities -return $formats] $nnodes 2]
    }

    # Print the conditions and it's connectivities
    incr ::write::current_mdpa_indent_level
    set s1 [mdpaIndent]
    for {set i 0} {$i <[llength $obj]} {incr i} {
        set nids [lindex $obj $i]
        set cndid 0
        if {$nnodes != 1} {
            set eid [lindex $elems $i]
            set cndid [objarray get $ConditionMap $eid]
        }
        if {$cndid == 0} {
            set cndid [incr iter]
            if {$nnodes != 1} {
                objarray set $ConditionMap $eid $cndid
            }
        }
        WriteString "${s1}$cndid 0 $nids"
    }
    incr ::write::current_mdpa_indent_level -1

    # Print the footer
    WriteString "${s}End Conditions"
    WriteString ""

    return $iter
}


proc write::writeConditionGroupedSubmodelPartsByUniqueId {cid groups_dict conditions_map} {
    set s [mdpaIndent]
    WriteString "${s}Begin SubModelPart $cid // Condition $cid"

    incr ::write::current_mdpa_indent_level
    set s1 [mdpaIndent]
    WriteString "${s1}Begin SubModelPartNodes"
    WriteString "${s1}End SubModelPartNodes"
    WriteString "${s1}Begin SubModelPartElements"
    WriteString "${s1}End SubModelPartElements"
    WriteString "${s1}Begin SubModelPartConditions"
    WriteString "${s1}End SubModelPartConditions"

    foreach group [dict keys $groups_dict] {
        if {[dict exists $groups_dict $group what]} {set what [dict get $groups_dict $group what]} else {set what ""}
        if {[dict exists $groups_dict $group tableid_list]} {set tableid_list [dict get $groups_dict $group tableid_list]} else {set tableid_list ""}
        write::writeGroupSubModelPartByUniqueId $cid $group $conditions_map $what $tableid_list
    }

    incr ::write::current_mdpa_indent_level -1
    WriteString "${s}End SubModelPart"
}


# what can be: nodal, Elements, Conditions or Elements&Conditions
proc write::writeGroupSubModelPartByUniqueId { cid group ConditionsMap {what "Elements"} {tableid_list ""} } {
    variable submodelparts

    set mid ""
    set what [split $what "&"]
    set group [GetWriteGroupName $group]
    if {![dict exists $submodelparts [list $cid ${group}]]} {
        # Add the submodelpart to the catalog
        set good_name [write::transformGroupName $group]
        set mid "${cid}_${good_name}"
        dict set submodelparts [list $cid ${group}] $mid

        # Prepare the print formats
        incr ::write::current_mdpa_indent_level
        set s1 [mdpaIndent]
        incr ::write::current_mdpa_indent_level -1
        incr ::write::current_mdpa_indent_level 2
        set s2 [mdpaIndent]
        set gdict [dict create]
        set f "${s2}%5i\n"
        set f [subst $f]
        dict set gdict $group $f
        incr ::write::current_mdpa_indent_level -2

        # Print header
        set s [mdpaIndent]
        WriteString "${s}Begin SubModelPart $mid // Group $group // Subtree $cid"
        # Print tables
        if {$tableid_list ne ""} {
            set s1 [mdpaIndent]
            WriteString "${s1}Begin SubModelPartTables"
            foreach tableid $tableid_list {
                WriteString "${s2}$tableid"
            }
            WriteString "${s1}End SubModelPartTables"
        }
        WriteString "${s1}Begin SubModelPartNodes"
        GiD_WriteCalculationFile nodes -sorted $gdict
        WriteString "${s1}End SubModelPartNodes"
        WriteString "${s1}Begin SubModelPartElements"
        if {"Elements" in $what} {
            GiD_WriteCalculationFile elements -sorted $gdict
        }
        WriteString "${s1}End SubModelPartElements"
        WriteString "${s1}Begin SubModelPartConditions"
        if {"Conditions" in $what} {
            set elems [GiD_WriteCalculationFile elements -sorted -return $gdict]
            for {set i 0} {$i <[llength $elems]} {incr i} {
                set eid [objarray get $ConditionsMap [lindex $elems $i]]
                WriteString "${s2}[format %10d $eid]"
            }
        }
        WriteString "${s1}End SubModelPartConditions"
        WriteString "${s}End SubModelPart"
    }
    return $mid
}

