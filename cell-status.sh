#!/bin/bash
# Fred Denis -- May 2019 -- fred.denis3@gmail.com -- http://unknowndba.blogspot.com
# cell-status.sh - an overview of your Exadata cell and grid disks (http://bit.ly/2VxJIUH)
# Copyright (C) 2021 Fred Denis
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#
# More info and git repo: http://bit.ly/2VxJIUH -- https://github.com/freddenis/oracle-scripts
#
# The current script version is 20211111
#
# History :
#
# 20211111 - Fred Denis - GPLv3 licence
# 20211019 - Fred Denis - Code cleaning, set a default cell_group which is $HOME/cell_group as it is mainly
#                           what everybody uses so it makes sense not to have to specify it at each execution
# 20200914 - Fred Denis - Passing a cell_group file now works correctly
# 20190510 - Fred Denis - Initial release
#
# Variables
#
    NB_PER_LINE=$(bc <<< "`tput cols`/30")                                  # Number of DG to show per line,  can be changed with -n option
            TMP=$(mktemp)                                                   # A tempfile
           TMP2=$(mktemp)                                                   # A tempfile
 SHOW_BAD_DISKS="NO"                                                        # Shows the details of the bad disks (-v option)
      DBMACHINE="/opt/oracle.SupportTools/onecommand/databasemachine.xml"   # databasemachine.xml file
     CELL_GROUP="${HOME}/cell_group"                                        # default cell_group file as it is usually what everybody uses
#
# User used to connect to the cells `basename $0` -h for more information on this
#
           USER="root"                                                      # User to connect to the cells (-u option)
    NONROOTUSER="cellmonitor"                                               # User to connect to the cells if a non root user runs cell-status.sh (-u option)
    # If root is not used to run the script it is then less likely than root SSH keys will be deployed for this user
    # We then use ${NONROOTUSER} to connect
    if [[ $(id -u) -ne 0 ]]; then
	USER="${NONROOTUSER}"
    fi
#
# An usage function
#
usage()
{
printf "\n\033[1;37m%-8s\033[m\n" "NAME"                ;
cat << END
    cell-status.sh - an overview of your Exadata cell and grid disks (http://bit.ly/2VxJIUH)
END
printf "\n\033[1;37m%-8s\033[m\n" "SYNOPSIS"            ;
cat << END
    $0 [-v] [-u] [-c] [-o] [-f] [-n] [-h]
END
printf "\n\033[1;37m%-8s\033[m\n" "DESCRIPTION"         ;
cat << END
    $(basename $0) shows a status of the Cell disks and the Grid disks of all the cells of an Exadata
    It has be be executed by a user with SSH equivalence on the cell servers
        - If $(basename $0) is executed as root, then $USER is used to connect to the cells
        - If $(basename $0) is executed as a non root user, then $NONROOTUSER is used to connect to the cells
        - You can change this behavior by forcing the use of a specific user with the -u option
    About the cells $(basename $0) reports about:
        - If $(basename $0) is executed as root:
            The default cell_group file "${CELL_GROUP}" file is used
            If "${CELL_GROUP}" does not exist:
                - on < X8M it uses ibhosts to build the list of cells to connect to
                - on >= X8M, it fails as there is no ibhosts so a hardcoded cell_group file has to be specified (-c option)
        - If $(basename $0) is executed as a non root user, it uses the databasemachine.xml file to build the list of cells to connect to
END
printf "\n\033[1;37m%-8s\033[m\n" "OPTIONS"             ;
cat << END
    -v      Shows the details of the bad disks (with error or bad status)
    -u      User to connect to the cells (if the default does not suit you)
    -c -C   Specify a file which contains the cell list to connect to (aka cell_group), default is: "${CELL_GROUP}"

    -o      Save the output of the dcli commands in a file ($(basename $0) -o outputfile.log)
    -f      Use a file generated by the -o option as input ($(basename $0) -f outputfile.log)
    -n      Number of diskgroups to show per line (if not specified, $(basename $0) adapts it to the terminal size)

    -h      Shows this help

END
exit 123
}
#
# Options
#
while getopts "ho:f:n:vu:c:C:" OPT; do
    case ${OPT} in
    o)           OUT="${OPTARG}"                                                            ;;
    f)            IN="${OPTARG}"                                                            ;;
    n)   NB_PER_LINE="${OPTARG}"                                                            ;;
    v)SHOW_BAD_DISKS="YES"                                                                  ;;
    u)          USER="${OPTARG}"                                                            ;;
    c)    CELL_GROUP="${OPTARG}"                                                            ;;
    C)    CELL_GROUP="${OPTARG}"                                                            ;;
    h)         usage                                                                        ;;
    \?)        echo "Invalid option: -$OPTARG" >&2; usage                                   ;;
    esac
done

if [[ -z "${IN}" ]]; then                # No input file specified, we dynamically find the info from the cells
   if [[ -z "${CELL_GROUP}" ]]; then
        if [[ $(id -u) -eq 0 ]]; then    # root is executing the script
                 ibhosts | sed s'/"//' | grep cel | awk '{print $6}' | sort > ${TMP2}   # list of cells
        else    # When no root
                if [[ -f "${DBMACHINE}" ]]; then
                        cat "${DBMACHINE}" | awk 'BEGIN {FS="<|>"} {if ($3 == "cellnode") {while(getline) {if ($2 == "ADMINNAME") {print $3; break; } } }}' > "${TMP2}"
                else
                        cat << END
                        Cannot access ${DBMACHINE}, cannot continue.
END
                        exit 255
                fi
        fi
   fi
        if [[ -n "${CELL_GROUP}" && -f "${CELL_GROUP}" ]]; then            # If a cell_group file is specified we use it
                cp "${CELL_GROUP}" "${TMP2}"
        fi
        dcli -g "${TMP2}" -l "${USER}" "echo celldisk; cellcli -e list celldisk attributes name,status,size,errorcount,disktype; echo BREAK; echo griddisk; cellcli -e list griddisk attributes asmDiskGroupName,name,asmmodestatus,asmdeactivationoutcome,size,errorcount,disktype; echo BREAK_CELL" > "${TMP}"
        IN="${TMP}"
fi
if [[ -n "${OUT}" ]]; then      # Output file specified, we save the cell infos in and we exit
        cp "${TMP}" "${OUT}"
        rm "${TMP}"
        cat << END
        Output file ${OUT} has been successfully generated.
END
exit 456
fi
if [[ ! -f "${IN}" ]]; then
        cat << !
        Cannot find the file ${IN}; cannot continue.
!
exit 123
fi
#
# Show the Exadata model if possible
#
printf "\n"
if [ -f "${DBMACHINE}" ] && [ -r "${DBMACHINE}" ]; then
        cat << !
                Cluster is a $(grep -i MACHINETYPES ${DBMACHINE} | sed s'/\t*//' | sed -e s':</*MACHINETYPES>::g' -e s'/^ *//' -e s'/ *$//')
!
else
        printf "\n"
fi
#
# Read the information from the cells and make nice tables
#
awk -v nb_per_line="$NB_PER_LINE" -v show_bad_disks="$SHOW_BAD_DISKS" 'BEGIN\
        {
          # Some colors
             COLOR_BEGIN =       "\033[1;"                      ;
               COLOR_END =       "\033[m"                       ;
                     RED =       "31m"                          ;
                   GREEN =       "32m"                          ;
                  YELLOW =       "33m"                          ;
                    BLUE =       "34m"                          ;
                    TEAL =       "36m"                          ;
                   WHITE =       "37m"                          ;
                  NORMAL =        "0m"                          ;
          BACK_LIGHTBLUE =      "104m"                          ;
          RED_BACKGROUND =       "41m"                          ;
        # Column size
                COL_CELL =      20                              ;
            COL_DISKTYPE =      26                              ;
                  COL_NB =      COL_DISKTYPE/3                  ;
        }
        #
        # A function to center the outputs with colors
        #
        function center( str, n, color, sep)
        {       right = int((n - length(str)) / 2)                                                                    ;
              left  = n - length(str) - right                                                                         ;
              return sprintf(COLOR_BEGIN color "%" left "s%s%" right "s" COLOR_END sep, "", str, "" )                 ;
        }
        #
        # A function that just print a "---" white line
        #
        function print_a_line(size)
        {
               if ( ! size)
               {       size = COL_DB+COL_VER+(COL_NODE*n)+COL_TYPE+n+3                  ;
               }
               printf("%s", COLOR_BEGIN WHITE)                                          ;
               for (k=1; k<=size; k++) {printf("%s", "-");}                             ;
               printf("%s", COLOR_END"\n")                                              ;
        }
        {       sub (":", "", $1)                                                       ;
                if ($2 == "celldisk")
                {       cell = $1                                                       ;
                        tab_cell[cell] = cell                                           ;
                        while (getline)
                        {       sub (":", "", $1)                                       ;
                                if ($2 == "BREAK")
                                {
                                        break                                           ;
                                }
                                if ($3 == "normal")
                                {
                                        tab_status[cell,$NF,$3]++                       ;       # With status = normal
                                } else {
                                        bad_cell_disks[$0] = $0                         ;       # Bad disks with status != normal
                                }
                                tab_err[cell,$NF]+=$(NF-1)                              ;       # Disks with errors
                                if ($(NF-1) > 0)
                                {       bad_cell_disks[$0] = $0                         ;       # Details to show with -v option
                                }
                                tab_nbdisks[cell,$NF]++                                 ;       # NB disks per distype
                                tab_disktype[$NF]=$NF                                   ;       # Disktypes
                        }
                }       # End if ($2 == "celldisk")
                if ($2 == "griddisk")
                {       cell = $1                                                       ;
                        while(getline)
                        {       sub (":", "", $1)                                       ;
                                if ($2 == "BREAK_CELL")
                                {
                                        break                                           ;
                                }
                                if ($3 != "UNUSED")                                             # Unused disks have no DG
                                {
                                        tab2_err[cell,$2]+=$7                           ;       # Grid disks with errors
                                        if ($7 > 0)
                                        {       bad_grid_disks[$0] = $0                 ;       # Details to show with -v option
                                        }
                                        tab2_nbdisks[cell,$2]++                         ;       # Nb disks per diskgroup
                                        tab2_dgs[$2]=$2                                 ;       # Diskgroups
                                        if (tolower($5) != "yes")                               # asmDeactivationOutcome
                                        {       tab2_deact[cell,$2]="no"                ;
                                                bad_grid_disks[$0] = $0                 ;       # Details to show with -v option
                                        }
                                        if ($4 == "ONLINE")
                                        {       tab2_status[cell,$2]++                  ;       # cell,DG
                                        } else {
                                                tab2_bad[cell,$2]++                     ;       # bad status disks
                                                bad_grid_disks[$0] = $0                 ;       # Details to show with -v option
                                        }
                                }
                        }
                }       # End if ($2 == "griddisk")

        }
        function print_blue_hyphen(size, sep)
        {
                printf ("%s", center("--", size, BLUE, sep))                            ;       # Just print a blue "--"
        }
        function print_red_cross(size, sep)
        {
                printf ("%s", center("xx", size, COLOR_STATUS, sep))                    ;       # Just print a red "xx"
        }
        function print_legend()
        {       # A legend behind the tables
                printf(COLOR_BEGIN BLUE " %-"3"s" COLOR_END, "--")                              ;
                printf(COLOR_BEGIN WHITE " %-"12"s |" COLOR_END, ": Unused disks")              ;
                printf(COLOR_BEGIN RED " %-"3"s" COLOR_END, "xx")                               ;
                printf(COLOR_BEGIN WHITE " %-"20"s |" COLOR_END, ": Not ONLINE disks")          ;
                printf(COLOR_BEGIN RED_BACKGROUND " %-"3"s" COLOR_END, "  ")                    ;
                printf(COLOR_BEGIN WHITE " %-"20"s" COLOR_END, ": asmDeactivationOutcome is NOT yes");
        }
        function print_table(in_array, in_title, in_header)
        {
                # Print a table from in_array adapting every column to the largest colum in the table
                # including the header from in_header hich is a string collectyion separated by blank like "col1 col2 col3"
                # Only the first column always have a COL_CELL size to match with the other tables to keep nice output
                # It then always make a nice table and it was fun to code :)
                a=asort(in_array, sorted)                                               ;
                sorted[a+1]= in_header                                                  ;       # Table header
                print sorted[0]                                          ;
                printf("%s", center(in_title, COL_CELL, TEAL))       ;
                printf("\n")                                                            ;
                for (i=1; i<=a+1; i++)                                                          # For each line
                {       split(sorted[i], bad)                            ;
                        for (j=1; j<=length(bad); j++)                                          # For each column
                        {       if (j == 1)                                                     # To have the cell column same on all tables
                                {       size[j] = COL_CELL                              ;
                                } else {
                                        if (length(bad[j])>size[j]) { size[j] = length(bad[j])+2}       ;
                                }
                        }
                }
                line_size=0                                                             ;
                for (k=1; k<=length(size); k++) { line_size+=size[k]                    ;}
                for (i=1; i<=a; i++)                                                            # For each line
                {       split(sorted[i], bad)                            ;
                        if (i == 1)
                        {       for (j=1; j<=length(bad); j++)                                  # For each column
                                {       split(sorted[a+1], title)        ;
                                        printf("%s", center(title[j], size[j], NORMAL, "|"))            ;
                                }
                                printf("\n")                                            ;
                                print_a_line(line_size+length(size))                    ;
                        }
                        for (j=1; j<=length(bad); j++)  # Each column                           # For each column
                        {
                                printf("%s", center(bad[j], size[j], NORMAL, "|"))      ;
                        }
                        printf("\n")                                                    ;
                }
                print_a_line(line_size+length(size))                                    ;
        }
        function print_griddisk_header(i)
        {
                printed=0                                                               ;
                printf("\n\n", "")                                                        ;
                printf ("%s", center("Grid Disks", COL_CELL, TEAL, "|"))                ;

                for (j=i; j<i+nb_per_line; j++)
                {
                        dg=dgs_sorted[j]                                                ;       # To ease the naming below

                        if (j > nb_dgs)         # Everything is printed so we stop even if line is not full
                        {       break                                                   ;
                        }
                        printf ("%s", center(dg, COL_DISKTYPE, WHITE, "|"))             ;
                }
                printf("\n")                                                            ;
                printf ("%s", center(" ", COL_CELL, WHITE, "|"))                        ;

                for (j=i; j<i+nb_per_line; j++)
                {
                        if (j > nb_dgs)         # Everything is printed so we stop even if line is not full
                        {       break                                                   ;
                        }
                        printf ("%s", center("Nb", COL_NB, WHITE, "|"))                 ;
                        printf ("%s", center("Online", COL_NB, WHITE, "|"))             ;
                        printf ("%s", center("Errors", COL_NB, WHITE, "|"))             ;
                        printed++                                                       ;
                }
                printf("\n")                                                            ;
                print_a_line(COL_CELL+COL_DISKTYPE*printed+printed+1)                   ;
        }
        END\
        {       # Sort the arrays
                nb_cells=asort(tab_cell, tab_cell_sorted)                               ;
                #
                # CELL DISKS
                #
                # Disk Types
                printf("\n", "")                                                        ;
                printf ("%s", center("Cell Disks", COL_CELL, TEAL, "|"))                ;
                for (disktype in tab_disktype)
                {
                        printf ("%s", center(disktype, COL_DISKTYPE, WHITE, "|"))       ;
                }
                printf("\n")                                                            ;
                printf ("%s", center(" ", COL_CELL, WHITE, "|"))                        ;
                for (disktype in tab_disktype)
                {
                        printf ("%s", center("Nb", COL_NB, WHITE, "|"))                 ;
                        printf ("%s", center("Normal", COL_NB, WHITE, "|"))             ;
                        printf ("%s", center("Errors", COL_NB, WHITE, "|"))             ;
                }
                printf("\n")                                                            ;
                print_a_line(COL_CELL+COL_DISKTYPE*length(tab_disktype)+length(tab_disktype)+1) ;

                for (x=1; x<=nb_cells; x++)
                {
                        cell=tab_cell_sorted[x]                                         ;
                        printf ("%s", center(cell, COL_CELL, WHITE, "|"))               ;
                        for (y in tab_status)
                        {       split(y,sep,SUBSEP)                                     ;
                                if (sep[1] == cell)
                                {       for (disktype in tab_disktype)
                                        {
                                                COLOR_ERROR=GREEN                       ;
                                                COLOR_STATUS=GREEN                      ;

                                                # Nb disks
                                                printf ("%s", center(tab_nbdisks[cell,disktype], COL_NB, WHITE, "|"))                   ;

                                                # Disks status
                                                if (tab_status[cell,disktype,sep[3]]<tab_nbdisks[cell,disktype]) { COLOR_STATUS=RED;}
                                                printf ("%s", center(tab_status[cell,disktype,sep[3]], COL_NB, COLOR_STATUS, "|"))      ;

                                                # Number of error
                                                if (tab_err[cell,disktype]>0)   { COLOR_ERROR=RED;      }
                                                printf ("%s", center(tab_err[cell,disktype], COL_NB, COLOR_ERROR, "|"))                 ;
                                        }
                                        break                                           ;
                                }
                        }
                        printf("\n")                                                    ;
                }
                print_a_line(COL_CELL+COL_DISKTYPE*length(tab_disktype)+length(tab_disktype)+1)                                         ;

                #
                # Print the failed cell disks details contained in the array bad_cell_disks
                #
                if (tolower(show_bad_disks) == "yes")
                {
                        if (length(bad_cell_disks) > 0)
                        {       print_table(bad_cell_disks, "Failed Cell Disks details", "Cell Name Status Size Nb_Error Disktype")   ;
                        }
                }

                #
                # GRID DISKS
                #
                nb_dgs=asort(tab2_dgs, dgs_sorted)                                      ;

                for (i=1; i<=nb_dgs; i+=nb_per_line)
                {
                        print_griddisk_header(i)                                        ;
                        for (x=1; x<=nb_cells; x++)
                        {
                                      cell=tab_cell_sorted[x]                           ;        # To ease the naming below
                                nb_printed=0    ;
                                printf ("%s", center(cell, COL_CELL, WHITE, "|"))       ;
                                for (k=i; k<i+nb_per_line; k++)
                                {
                                        if (k > nb_dgs)                                         # Everything is printed so we stop even if line is not full
                                        {       break                                   ;
                                        }
                                        dg=dgs_sorted[k]                                ;       # To ease the naming below

                                        if (tab2_deact[cell,dg])                                # asmdeactivationoutcome is NOT yes
                                        {
                                                     COLOR_ERROR=RED_BACKGROUND         ;
                                                    COLOR_STATUS=RED_BACKGROUND         ;
                                                COLOR_STATUS_BAD=RED_BACKGROUND         ;
                                                  COLOR_NB_DISKS=RED_BACKGROUND         ;
                                        } else {
                                                     COLOR_ERROR=GREEN                  ;
                                                    COLOR_STATUS=GREEN                  ;
                                                 COLOR_STATUS_BAD=RED                   ;
                                                   COLOR_NB_DISKS=WHITE                 ;
                                        }

                                        if (tab2_nbdisks[cell,dg])
                                        {       printf ("%s", center(tab2_nbdisks[cell,dg], COL_NB, COLOR_NB_DISKS, "|"))       ;      # NB disks
                                        } else {
                                                print_blue_hyphen(COL_NB, "|")          ;
                                        }

                                        if (tab2_status[cell,dg]<tab2_nbdisks[cell,dg]) { COLOR_STATUS=COLOR_STATUS_BAD;}
                                        if (tab2_bad[cell,dg] > 0)
                                        {       print_red_cross(COL_NB, "|")            ;
                                        } else {
                                                if (tab2_status[cell,dg])
                                                {       printf ("%s", center(tab2_status[cell,dg], COL_NB, COLOR_STATUS, "|"))  ; # Nb disks with ONLINE status
                                                } else {
                                                        print_blue_hyphen(COL_NB, "|")  ;
                                                }
                                        }

                                        if (tab2_err[cell,dg]>0)    { COLOR_ERROR=COLOR_STATUS_BAD;      }
                                        if (tab2_err[cell,dg] != "")
                                        {       printf ("%s", center(tab2_err[cell,dg], COL_NB, COLOR_ERROR, "|"))              ;     # NB errors
                                        } else {
                                                print_blue_hyphen(COL_NB, "|")          ;
                                        }
                                        nb_printed++                                    ;
                                }
                                printf("\n")                                            ;
                        }
                        print_a_line(COL_CELL+COL_DISKTYPE*nb_printed+nb_printed+1)     ;
                        print_legend()                                                  ;
                }       # End         for (i=1; i<=nb_dgs; i++)

                # Show bad grid disks
                if (tolower(show_bad_disks) == "yes")
                {       printf("\n\n")                                                          ;
                        printf("%s", center("Failed Grid Disks details", COL_CELL, TEAL))       ;
                        printf("\n")                                                            ;
#                       print_table(bad_grid_disks, "Failed Grid Disks details", "Cell asmDGName Name Status Deact Size NBError Disktype")      ;
                        if (length(bad_grid_disks) > 0)
                        {
                                a=asort(bad_grid_disks, bad_grid_disks_sorted)                  ;
                                printf("%-14s%-24s%12s%16s%6s%8s%6s%16s\n", "cell", "asmDGName", "name","status", "deactoutcome", "size", "error" ,"disktype" )       ;
                                for (i=1; i<=a; i++)
                                {
                                        printf ("%s\n", bad_grid_disks_sorted[i])               ;
                                }
                        }
                        printf("\n")                                                            ;
                }
        printf("\n")                                                                    ;
        printf("\n")                                                                    ;
        }' "${IN}"
#
# Delete tempfiles
#
for F in "${TMP}" "${TMP2}"; do
    rm -f "${F}"
done

#****************************************************************#
#               E N D      O F       S O U R C E                *#
#****************************************************************#

