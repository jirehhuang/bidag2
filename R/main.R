#'Structure learning with the order MCMC algorithm
#'
#'This function implements the order MCMC algorithm for the structure learning of Bayesian networks. This function can be used
#'for MAP discovery and for sampling from the posterior distribution of DAGs given the data.
#'Due to the superexponential size of the search space as the number of nodes increases, the
#'MCMC search is performed on a reduced search space.
#'By default the search space is limited to the skeleton found through the PC algorithm by means of conditional independence tests
#'(using the functions \code{\link[pcalg]{skeleton}} and \code{\link[pcalg]{pc}} from the `pcalg' package [Kalisch et al, 2012]).
#'It is also possible to define an arbitrary search space by inputting an adjacency matrix, for example estimated by partial correlations or other network algorithms.
#'Also implemented is the possibility to expand the default or input search space, by allowing each node in the network to have one additional parent.  This offers improvements in the learning and sampling of Bayesian networks.
#' @param scorepar an object of class \code{scoreparameters}, containing the data and score parameters, see constructor function \code{\link{scoreparameters}}
#' @param MAP logical, if TRUE (default) the search targets the MAP DAG (a DAG with maximum score),
#' if FALSE at each MCMC step a DAG is sampled from the order proportionally to its score
#' @param plus1 logical, if TRUE (default) the search is performed on the extended search space
#' @param chainout logical, if TRUE the saved MCMC steps are returned, TRUE by default
#' @param scoreout logical, if TRUE the search space and score tables are returned, FALSE by default
#' @param moveprobs a numerical vector of 4 values in \code{\{0,1\}} corresponding to the probabilities of the following MCMC moves in the order space
#' \itemize{
#' \item exchanging 2 random nodes in the order
#' \item exchanging 2 adjacent nodes in the order
#' \item placing a single node elsewhere in the order
#' \item staying still
#' }
#' @param iterations integer, the number of MCMC steps, the default value is \eqn{6n^{2}\log{n}}
#' @param stepsave integer, thinning interval for the MCMC chain, indicating the number of steps between two output iterations, the default is \code{iterations/1000}
#' @param alpha numerical significance value in \code{\{0,1\}} for the conditional independence tests at the PC algorithm stage
#' @param gamma tuning parameter which transforms the score by raising it to this power, 1 by default
#' @param cpdag logical, if TRUE the CPDAG returned by the PC algorithm will be used as the search
#'space, if FALSE (default) the full undirected skeleton will be used as the search space
#' @param hardlimit integer, limit on the size of parent sets in the search space; by default 14 when MAP=TRUE and 20 when MAP=FALSE
#' @param verbose logical, if TRUE messages about the algorithm's progress will be printed, FALSE by default
#' @param compress logical, if TRUE adjacency matrices representing sampled graphs will be stored as a sparse Matrix (recommended); TRUE by default
#' @param startspace (optional) a square matrix, of dimensions equal to the number of nodes, which defines the search space for the order MCMC in the form of an adjacency matrix. If NULL, the skeleton obtained from the PC-algorithm will be used. If \code{startspace[i,j]} equals to 1 (0) it means that the edge from node \code{i} to node \code{j} is included (excluded) from the search space. To include an edge in both directions, both \code{startspace[i,j]} and \code{startspace[j,i]} should be 1.
#' @param blacklist (optional) a square matrix, of dimensions equal to the number of nodes, which defines edges to exclude from the search space. If \code{blacklist[i,j]} equals to 1 it means that the edge from node \code{i} to node \code{j} is excluded from the search space.
#' @param scoretable (optional) object of class \code{scorespace} containing list of score tables calculated for example by the last iteration of the function \code{iterativeMCMC}. When not NULL, parameter \code{startspace} is ignored.
#' @param startorder (optional) integer vector of length n, which will be used as the starting order in the MCMC algorithm, the default order is random
#' @return Object of class \code{orderMCMC}, which contains log-score trace of sampled DAGs as well
#' as adjacency matrix of the maximum scoring DAG, its score and the order score. The output can optionally include DAGs sampled in MCMC iterations and the score tables.
#' Optional output is regulated by the parameters \code{chainout} and \code{scoreout}. See \code{\link{orderMCMC class}} for a detailed class structure.
#' @note see also extractor functions \code{\link{getDAG}}, \code{\link{getTrace}}, \code{\link{getSpace}}, \code{\link{getMCMCscore}}.
#'@references Friedman N and Koller D (2003). A Bayesian approach to structure discovery in bayesian networks. Machine Learning 50, 95-125.
#'@references Kalisch M, Maechler M, Colombo D, Maathuis M and Buehlmann P (2012). Causal inference using graphical models with the R package pcalg. Journal of Statistical Software 47, 1-26.
#'@references Geiger D and Heckerman D (2002). Parameter priors for directed acyclic graphical models and the characterization of several probability distributions. The Annals of Statistics 30, 1412-1440.
#'@references Kuipers J, Moffa G and Heckerman D (2014). Addendum on the scoring of Gaussian acyclic graphical models. The Annals of Statistics 42, 1689-1691.
#'@references Spirtes P, Glymour C and Scheines R (2000). Causation, Prediction, and Search, 2nd edition. The MIT Press.
#'@examples
#'\dontrun{
#'#find a MAP DAG with search space defined by PC and plus1 neighbourhood
#'Bostonscore<-scoreparameters("bge",Boston)
#'#estimate MAP DAG
#'orderMAPfit<-orderMCMC(Bostonscore)
#'summary(orderMAPfit)
#'#sample DAGs from the posterior distribution
#'ordersamplefit<-orderMCMC(Bostonscore,MAP=FALSE,chainout=TRUE)
#'plot(ordersamplefit)
#'}
#'@author Polina Suter, Jack Kuipers, the code partly derived from the order MCMC implementation from Kuipers J, Moffa G (2017) <doi:10.1080/01621459.2015.1133426>
#'@export
orderMCMC<-function(scorepar, MAP=TRUE, plus1=TRUE,chainout=FALSE, scoreout=FALSE, moveprobs=NULL,
                    iterations=NULL, stepsave=NULL, alpha=0.05, cpdag=FALSE, gamma=1,
                    hardlimit=ifelse(plus1,14,20),verbose=FALSE,compress=TRUE,
                    startspace=NULL, blacklist=NULL,startorder=NULL, scoretable=NULL) {
  if (is.null(moveprobs)) {
    prob1<-99
    if(scorepar$nsmall>3){ prob1<-round(6*99*scorepar$nsmall/(scorepar$nsmall^2+10*scorepar$nsmall-24)) }
    prob1<-prob1/100
    moveprobs<-c(prob1,0.99-prob1,0.01)
    moveprobs<-moveprobs/sum(moveprobs)
    moveprobs<-c(moveprobs[c(1,2)],0,moveprobs[3])
  }
  if(is.null(iterations)){
    if(scorepar$nsmall<26){
      iterations<-30000
    } else {
      iterations<-(6*scorepar$nsmall*scorepar$nsmall*log(scorepar$nsmall))-(6*scorepar$nsmall*scorepar$nsmall*log(scorepar$nsmall)) %% 1000
    }
  }
  if(is.null(stepsave)){
    stepsave<-floor(iterations/1000)
  }

  ordercheck<-checkstartorder(startorder,varnames=scorepar$labels.short,mainnodes=scorepar$mainnodes,
                              bgnodes=scorepar$static,DBN=scorepar$DBN,split=scorepar$split)

  if(ordercheck$errorflag) {
    stop(ordercheck$message)
  } else {
    startorder<-ordercheck$order
  }

  if(scorepar$DBN) { #flag for DBN structure learning with different initial and transition structures

    if(!is.null(blacklist)) {
      blacklist<-DBNbacktransform(blacklist,scorepar)
    }

    if(!is.null(scoretable)) {
      scoretable$adjacency<-DBNbacktransform(scoretable$adjacency,scorepar)
      scoretable$blacklist<-DBNbacktransform(scoretable$blacklist,scorepar)
    }

    if(!is.null(startspace)) {
      startspace<-DBNbacktransform(startspace,scorepar)
    }



    if(scorepar$split) { #we learn initial and transition structures separately
      if(scorepar$MDAG) {
        param1<-scorepar$paramsets[[scorepar$nsets]]
        param2<-scorepar$paramsets[[1]]
        param2$paramsets<-scorepar$paramsets[1:(scorepar$nsets-1)]
        param2$MDAG<-TRUE
      } else {
        param1<-scorepar$firstslice
        param2<-scorepar$otherslices
      }
      if(scoreout | !is.null(scoretable)) {
        cat("option scoreout always equals FALSE for DBNs with samestruct=FALSE, scoretable parameter is ignored \n")
      }

      result.trans<-orderMCMCmain(param=param2,iterations,stepsave,startorder=startorder$trans,
                                  moveprobs=moveprobs,alpha=alpha,cpdag=cpdag,scoretable=NULL,
                                  plus1=plus1,MAP=MAP,chainout=chainout, scoreout=FALSE,
                                  startspace=startspace$trans,blacklist=blacklist$trans,gamma=gamma,verbose=verbose,
                                  hardlimit=hardlimit,compress=compress)

      if(scorepar$learninit) {
        result.init<-orderMCMCmain(param=param1,iterations,stepsave,startorder=startorder$init,
                                   moveprobs=moveprobs,alpha=alpha,cpdag=cpdag,scoretable=NULL,
                                   plus1=plus1,MAP=MAP,chainout=chainout, scoreout=FALSE,
                                   startspace=startspace$init,blacklist=blacklist$init,gamma=gamma,verbose=verbose,
                                   hardlimit=hardlimit,compress=compress)
        result<-mergeDBNres(result.init,result.trans,scorepar,algo="order")
      } else {
        result<-result.trans
      }


    } else  {

      result<-orderMCMCmain(param=scorepar,iterations,stepsave,startorder=startorder,
                            moveprobs=moveprobs,alpha=alpha,cpdag=cpdag,scoretable=scoretable,
                            plus1=plus1,MAP=MAP,chainout=chainout, scoreout=scoreout,
                            startspace=startspace,blacklist=blacklist,gamma=gamma,verbose=verbose,
                            hardlimit=hardlimit,compress=compress)
    }
  }

  else {
    result<-orderMCMCmain(param=scorepar,iterations,stepsave,startorder=startorder,
                          moveprobs=moveprobs,alpha=alpha,cpdag=cpdag,scoretable=scoretable,
                          plus1=plus1,MAP=MAP,chainout=chainout, scoreout=scoreout,
                          startspace=startspace,blacklist=blacklist,gamma=gamma,verbose=verbose,
                          hardlimit=hardlimit,compress=compress)
  }


  if(plus1) {
    result$info$algo<-"plus1 order MCMC"
  } else {
    result$info$algo<-"base order MCMC"
  }
  result$info$DBN<-scorepar$DBN
  if(scorepar$DBN) {
    result$info$nsmall<-scorepar$nsmall
    result$info$bgn<-scorepar$bgn
    result$info$split<-scorepar$split
  }
  if(is.null(startspace)) {
    result$info$spacealgo<-"PC"
  } else {
    result$info$spacealgo<-"user defined matrix"
  }
  result$info$iterations<-iterations
  result$info$samplesteps<-length(result$trace)
  if(MAP) {
    result$info$sampletype<-"MAP"
  } else {
    result$info$sampletype<-"sample"
  }
  result$info$startorder<-startorder
  result$info$fncall<-match.call()

  attr(result,"class")<-"orderMCMC"

  return(result)

}

#'DAG structure sampling with partition MCMC
#'
#'This function implements the partition MCMC algorithm for the structure learning of Bayesian networks.  This procedure provides an unbiased sample from the posterior distribution of DAGs given the data.
#'The search space can be defined either by a preliminary run of the function \code{iterativeMCMC} or by a given adjacency matrix (which can be the full matrix with zero on the diagonal, to consider the entire space of DAGs, feasible only for a limited number of nodes).
#'
#' @param scorepar an object of class \code{scoreparameters}, containing the data and scoring parameters;  see constructor function \code{\link{scoreparameters}}.
#' @param moveprobs (optional) a numerical vector of 5 values in \code{\{0,1\}} corresponding to the following MCMC move probabilities in the space of partitions:
#' \itemize{
#' \item swap any two elements from different partition elements
#' \item swap any two elements in adjacent partition elements
#' \item split a partition element or join one
#' \item move a single node into another partition element or into a new one
#' \item stay still
#' }
#' @param iterations integer, the number of MCMC steps, the default value is \eqn{20n^{2}\log{n}}
#' @param stepsave integer, thinning interval for the MCMC chain, indicating the number of steps between two output iterations, the default is \code{iterations/1000}
#' @param alpha numerical significance value in \code{\{0,1\}} for the conditional independence tests at the PC algorithm stage
#' @param gamma tuning parameter which transforms the score by raising it to this power, 1 by default
#' @param verbose logical, if set to TRUE (default) messages about progress will be printed
#' @param scoreout logical, if TRUE the search space and score tables are returned, FALSE by default
#' @param compress logical, if TRUE adjacency matrices representing sampled graphs will be stored as a sparse Matrix (recommended); TRUE by default
#' @param startspace (optional) a square matrix, of dimensions equal to the number of nodes, which defines the search space for the order MCMC in the form of an adjacency matrix; if NULL, the skeleton obtained from the PC-algorithm will be used. If \code{startspace[i,j]} equals to 1 (0) it means that the edge from node \code{i} to node \code{j} is included (excluded) from the search space. To include an edge in both directions, both \code{startspace[i,j]} and \code{startspace[j,i]} should be 1.
#' @param blacklist (optional) a square matrix, of dimensions equal to the number of nodes, which defines edges to exclude from the search space; if \code{blacklist[i,j]=1} it means that the edge from node \code{i} to node \code{j} is excluded from the search space
#' @param scoretable (optional) object of class \code{scorespace} containing list of score tables calculated for example by the last iteration of the function \code{iterativeMCMC}. When not NULL, parameter \code{startspace} is ignored
#' @param startDAG (optional) an adjacency matrix of dimensions equal to the number of nodes, representing a DAG in the search space defined by startspace.  If startspace is defined but \code{startDAG} is not, an empty DAG will be used by default
#' @return Object of class \code{partitionMCMC}, which contains log-score trace as well
#' as adjacency matrix of the maximum scoring DAG, its score and the order score. Additionally, returns all sampled DAGs (represented by their adjacency matrices), their scores,
#'orders and partitions See \code{\link{partitionMCMC class}}.
#' @note see also extractor functions \code{\link{getDAG}}, \code{\link{getTrace}}, \code{\link{getSpace}}, \code{\link{getMCMCscore}}.
#'@references Kuipers J and Moffa G (2017). Partition MCMC for inference on acyclic digraphs. Journal of the American Statistical Association 112, 282-299.
#'@references Geiger D and Heckerman D (2002). Parameter priors for directed acyclic graphical models and the characterization of several probability distributions. The Annals of Statistics 30, 1412-1440.
#'@references Heckerman D and Geiger D (1995). Learning Bayesian networks: A unification for discrete and Gaussian domains. In Eleventh Conference on Uncertainty in Artificial Intelligence, pages 274-284.
#'@references Kalisch M, Maechler M, Colombo D, Maathuis M and Buehlmann P (2012). Causal inference using graphical models with the R package pcalg. Journal of Statistical Software 47, 1-26.
#'@references Kuipers J, Moffa G and Heckerman D (2014). Addendum on the scoring of Gaussian directed acyclic graphical models. The Annals of Statistics 42, 1689-1691.
#'@examples
#'\dontrun{
#'myScore<-scoreparameters("bge", Boston)
#'partfit<-partitionMCMC(myScore)
#'plot(partfit)
#'}
#'@import pcalg
#'@author Polina Suter, Jack Kuipers, the code partly derived from the partition MCMC implementation from Kuipers J, Moffa G (2017) <doi:10.1080/01621459.2015.1133426>
#'@export
partitionMCMC<-function(scorepar, moveprobs=NULL, iterations=NULL,  stepsave=NULL, alpha = 0.05, gamma=1,verbose=FALSE,
                        scoreout=FALSE,compress=TRUE,startspace=NULL, blacklist=NULL,scoretable=NULL, startDAG=NULL) {
  if (is.null(moveprobs)) {
    prob1start<-40/100
    prob1<-prob1start*100
    if(scorepar$nsmall>3){ prob1<-round(6*prob1*scorepar$nsmall/(scorepar$nsmall^2+10*scorepar$nsmall-24)) }
    prob1<-prob1/100
    prob2start<-99/100-prob1start
    prob2<-prob2start*100
    if(scorepar$nsmall>3){ prob2<-round(6*prob2*scorepar$nsmall/(scorepar$nsmall^2+10*scorepar$nsmall-24)) }
    prob2<-prob2/100
    moveprobs.partition<-c(prob1,prob1start-prob1,prob2start-prob2,prob2,0.01)
    moveprobs<-moveprobs.partition/sum(moveprobs.partition) # normalisation
  }
  if(is.null(iterations)){
    if(scorepar$nsmall<20){
      iterations<-20000
    } else {
      iterations<-(20*scorepar$nsmall*scorepar$nsmall*log(scorepar$nsmall))-(20*scorepar$nsmall*scorepar$nsmall*log(scorepar$nsmall)) %% 1000
    }
  }
  if(is.null(stepsave)){
    stepsave<-floor(iterations/1000)
  }

  if(scorepar$DBN) { #flag for DBN structure learning with different initial and transition structures

    if(!is.null(blacklist)) {
      blacklist<-DBNbacktransform(blacklist,scorepar)
    }

    if(!is.null(startspace)) {
      startspace<-DBNbacktransform(startspace,scorepar)
    }

    if(!is.null(startDAG)) {
      startDAG<-DBNbacktransform(startDAG,scorepar)
    }

    if(scorepar$split) { #we learn initial and transition structures separately
      if(scorepar$MDAG) {
        param1<-scorepar$paramsets[[scorepar$nsets]]
        param2<-scorepar$paramsets[[1]]
        param2$paramsets<-scorepar$paramsets[1:(scorepar$nsets-1)]
        param2$MDAG<-TRUE
      } else {
        param1<-scorepar$firstslice
        param2<-scorepar$otherslices
      }
      if(!is.null(scoretable)) {
        warning("for DBNs with samestruct=FALSE 'scoretable' parameter is ignored")
      }

      result.init<-partitionMCMCplus1sample(param=param1,startspace=startspace$init,
                                            blacklist=blacklist$init,moveprobs=moveprobs,
                                            numit=iterations,DAG=startDAG$init,stepsave=stepsave,
                                            scoretable=NULL,verbose=verbose,
                                            gamma=gamma,compress=compress,alpha=alpha)

      result.trans<-partitionMCMCplus1sample(param=param2,startspace=startspace$trans,
                                             blacklist=blacklist$trans,moveprobs=moveprobs,
                                             numit=iterations,DAG=startDAG$trans,stepsave=stepsave,
                                             scoretable=NULL,verbose=verbose,gamma=gamma,compress=compress,
                                             alpha=alpha)

      result<-mergeDBNres(result.init,result.trans,scorepar,algo="partition")

    } else {

      result<-partitionMCMCplus1sample(param=scorepar,startspace=startspace,blacklist=blacklist,
                                       moveprobs=moveprobs,numit=iterations,DAG=startDAG,
                                       stepsave=stepsave,scoretable=scoretable,verbose=verbose,
                                       gamma=gamma,compress=compress,alpha=alpha)
    }

  } else {
    result<-partitionMCMCplus1sample(param=scorepar,startspace=startspace,blacklist=blacklist,
                                     moveprobs=moveprobs,numit=iterations,DAG=startDAG,
                                     stepsave=stepsave,scoretable=scoretable,verbose=verbose,
                                     gamma=gamma,compress=compress,alpha=alpha)
  }


  result$info$DBN<-scorepar$DBN
  if(scorepar$DBN) {
    result$info$nsmall<-scorepar$nsmall
    result$info$bgn<-scorepar$bgn
    result$info$split<-scorepar$split
  }
  result$info$algo<-"plus1 partition MCMC"
  if(is.null(startspace)) {
    result$info$spacealgo<-"PC + iterative plus1 order MCMC"
  } else {
    result$info$spacealgo<-"user defined matrix"
  }
  result$info$iterations<-iterations
  result$info$samplesteps<-length(result$trace)
  result$info$sampletype<-"sample"
  result$info$fncall<-match.call()

  attr(result,"class")<-"partitionMCMC"
  return(result)
}


#'Structure learning with an iterative order MCMC algorithm on an expanded search space
#'
#'This function implements an iterative search for the maximum a posteriori (MAP) DAG,
#'by means of order MCMC (arXiv:1803.07859v3).  At each iteration, the current search space is expanded by
#'allowing each node to have up to one additional parent not already included in the search space.
#'By default the initial search space is obtained through the PC-algorithm (using the functions \code{\link[pcalg]{skeleton}} and \code{\link[pcalg]{pc}} from the `pcalg' package [Kalisch et al, 2012]).
#'At each iteration order MCMC is employed to search for the MAP DAG.
#'The edges in the MAP DAG are added to the initial search space to provide
#'the search space for the next iteration.  The algorithm iterates until no
#'further score improvements can be achieved by expanding the search space.
#'The final search space may be used for the sampling versions of \code{\link{orderMCMC}} and \code{\link{partitionMCMC}}.
#'
#' @param scorepar an object of class \code{scoreparameters}, containing the data and scoring parameters; see constructor function \code{\link{scoreparameters}}
#' @param moveprobs a numerical vector of 4 values in \code{\{0,1\}} corresponding to the probabilities of the following MCMC moves in the order space:
#' \itemize{
#' \item exchanging 2 random nodes in the order
#' \item exchanging 2 adjacent nodes in the order
#' \item placing a single node elsewhere in the order
#' \item staying still
#' }
#' @param iterations integer, the number of MCMC steps, the default value is \eqn{3.5n^{2}\log{n}}
#' @param stepsave integer, thinning interval for the MCMC chain, indicating the number of steps between two output iterations, the default is \code{iterations}/1000
#' @param MAP logical, if TRUE (default) the search targets the MAP DAG (a DAG with maximum score),
#' if FALSE at each MCMC step a DAG is sampled from the order proportionally to its score; when expanding a search space when MAP=TRUE all edges from the maximum scoring DAG are added
#'  to the new space, when MAP=FALSE only edges with posterior probability higher than defined by parameter \code{posterior} are added to the search space
#' @param posterior logical, when \code{MAP} set to FALSE defines posterior probability threshold for adding the edges to the search space
#' @param alpha numerical significance value in \code{\{0,1\}} for the conditional independence tests in the PC-stage
#' @param gamma tuning parameter which transforms the score by raising it to this power, 1 by default
#' @param startorder integer vector of length n, which will be used as the starting order in the MCMC algorithm, the default order is random
#' @param softlimit integer, limit on the size of parent sets beyond which adding undirected edges is restricted; below this
#' limit edges are added to expand the parent sets based on the undirected skeleton of the MAP DAG (or from its CPDAG, depending
#' on the parameter \code{mergecp}), above the limit only the directed edges are added from the MAP DAG;  the limit is 9 by default
#' @param hardlimit integer, limit on the size of parent sets beyond which the search space is not further expanded to prevent long runtimes; the limit is 12 by default
#' @param cpdag logical, if set to TRUE the equivalence class (CPDAG) found by the PC algorithm is used as a search
#'  space, when FALSE (default) the undirected skeleton used as a search space
#' @param mergetype defines which edges are added to the search space at each expansion iteration; three options are available 'dag', 'cpdag', 'skeleton'; 'skeleton' by default
#' @param accum logical, when TRUE at each search step expansion new edges are added to the current search space; when FALSE (default) the new edges are added to the starting space
#' @param compress logical, if TRUE adjacency matrices representing sampled graphs will be stored as a sparse Matrix (recommended); TRUE by default
#' @param plus1it (optional) integer, a number of iterations of search space expansion; by default the algorithm iterates until no score improvement can be achieved by further expanding the search space
#' @param startspace (optional) a square matrix, of dimensions equal to the number of nodes, which defines the search space for the order MCMC in the form of an adjacency matrix; if NULL, the skeleton obtained from the PC-algorithm will be used; if \code{startspace[i,j]} equals to 1 (0) it means that the edge from node \code{i} to node \code{j} is included (excluded) from the search space; to include an edge in both directions, both \code{startspace[i,j]} and \code{startspace[j,i]} should be 1
#' @param scoretable (optional) object of class \code{scorespace}. When not NULL, parameters \code{startspace} and \code{addspace} are ignored.
#' @param addspace (optional) a square matrix, of dimensions equal to the number of nodes, which defines the edges, which are added at to the search space only at the first iteration of iterative seach and do not necessarily stay afterwards; defined in the form of an adjacency matrix;  if \code{addspace[i,j]} equals to 1 (0) it means that the edge from node \code{i} to node \code{j} is included (excluded) from the search space; to include an edge in both directions, both \code{addspace[i,j]} and \code{addspace[j,i]} should be 1
#' @param blacklist (optional) a square matrix, of dimensions equal to the number of nodes, which defines edges to exclude from the search space; if \code{blacklist[i,j]} equals to 1 it means that the edge from node \code{i} to node \code{j} is excluded from the search space
#' \itemize{
#' \item "dag", then edges from maximum scoring DAG are added;
#' \item "cpdag", then the maximum scoring DAG is first converted to the CPDAG, from which all edges are added to the search space;
#' \item "skeleton", then the maximum scoring DAG is first converted to the skeleton, from which all edges are added to the search space
#' }
#' @param verbose logical, if TRUE (default) prints messages on the progress of execution
#' @param chainout logical, if TRUE the saved MCMC steps are returned, FALSE by default
#' @param scoreout logical, if TRUE the search space from the last plus1 iterations and the corresponding score tables are returned, FALSE by default
#' @param alphainit (optional) numerical, defines alpha that is used by the PC algorithm to learn initial structure of a DBN, ignored in static case
#' @return Object of class \code{iterativeMCMC}, which contains log-score trace as well as adjacency matrix of the maximum scoring DAG, its score and the order score.
#' The output can optionally include DAGs sampled in MCMC iterations and the score tables. Optional output is regulated by the parameters \code{chainout} and \code{scoreout}. See \code{\link{iterativeMCMC class}} for a detailed class structure.
#' @note see also extractor functions \code{\link{getDAG}}, \code{\link{getTrace}}, \code{\link{getSpace}}, \code{\link{getMCMCscore}}.
#'@references Kuipers J, Super P and Moffa G (2020). Efficient Sampling and Structure Learning of Bayesian Networks. (arXiv:1803.07859v3)
#'@references Friedman N and Koller D (2003). A Bayesian approach to structure discovery in bayesian networks. Machine Learning 50, 95-125.
#'@references Kalisch M, Maechler M, Colombo D, Maathuis M and Buehlmann P (2012). Causal inference using graphical models with the R package pcalg. Journal of Statistical Software 47, 1-26.
#'@references Geiger D and Heckerman D (2002). Parameter priors for directed acyclic graphical models and the characterization of several probability distributions. The Annals of Statistics 30, 1412-1440.
#'@references Kuipers J, Moffa G and Heckerman D (2014). Addendum on the scoring of Gaussian directed acyclic graphical models. The Annals of Statistics 42, 1689-1691.
#'@references Spirtes P, Glymour C and Scheines R (2000). Causation, Prediction, and Search, 2nd edition. The MIT Press.
#'@examples
#'\dontrun{
#'Bostonpar<-scoreparameters("bge",Boston)
#'itfit<-iterativeMCMC(Bostonpar, chainout=TRUE, scoreout=TRUE)
#'plot(itfit)
#'}
#'@import pcalg
#'@importFrom methods new
#'@importFrom graphics lines
#'@importFrom graphics par
#'@importFrom graphics layout
#'@importFrom graphics legend
#'@importFrom stats cor
#'@importFrom stats cov
#'@importFrom stats cov.wt
#'@importFrom stats pchisq
#'@importFrom stats runif
#'@importFrom stats rnorm
#'@importFrom utils data
#'@importFrom utils flush.console
#'@importFrom utils tail
#'@importFrom Rgraphviz makeNodeAttrs
#'@importFrom graph subGraph
#'@importFrom graph nodes
#'@importFrom graph nodeRenderInfo
#'@importFrom graph graph.par
#'@importFrom graph plot
#'@importFrom graph numNodes
#'@importFrom graphics text
#'@importFrom Rcpp evalCpp
#'@importFrom graphics abline
#'@importFrom utils head
#'@importFrom Matrix Matrix
#'@importFrom methods is
#'@importFrom coda mcmc
#'@importFrom coda mcmc.list
#'@useDynLib bidag, .registration=TRUE
#'@rdname iterativeMCMC
#'@export iterativeMCMC
#'@author Polina Suter, Jack Kuipers
iterativeMCMC<-function(scorepar, MAP=TRUE,posterior=0.5, softlimit=9, hardlimit=12, alpha=0.05, gamma=1, verbose=TRUE, chainout=FALSE, scoreout=FALSE, cpdag=FALSE,
                        mergetype="skeleton",iterations=NULL,moveprobs=NULL,stepsave=NULL,startorder=NULL,
                        accum=FALSE, compress=TRUE,plus1it=NULL,startspace=NULL,blacklist=NULL,addspace=NULL,scoretable=NULL, alphainit=NULL) {

  if (is.null(moveprobs)) {
    prob1<-99
    if(scorepar$nsmall>3){ prob1<-round(6*99*scorepar$nsmall/(scorepar$nsmall^2+10*scorepar$nsmall-24)) }
    prob1<-prob1/100
    moveprobs<-c(prob1,0.99-prob1,0.01)
    moveprobs<-moveprobs/sum(moveprobs) # normalisation
    moveprobs<-c(moveprobs[c(1,2)],0,moveprobs[3])
  }
  if(is.null(iterations)) {
    if(scorepar$nsmall<26){
      iterations<-25000
    } else {
      iterations<-(3.5*scorepar$nsmall*scorepar$nsmall*log(scorepar$nsmall))-(3.5*scorepar$nsmall*scorepar$nsmall*log(scorepar$nsmall)) %% 1000
    }
  }
  if(is.null(stepsave)) {
    stepsave<-floor(iterations/1000)
  }

  ordercheck<-checkstartorder(startorder,varnames=scorepar$labels.short,mainnodes=scorepar$mainnodes,
                              bgnodes=scorepar$static,DBN=scorepar$DBN,split=scorepar$split)

  if(ordercheck$errorflag) {
    stop(ordercheck$message)
  } else {
    startorder<-ordercheck$order
  }

  if(scorepar$DBN) { #flag for DBN structure learning with different initial and transition structures

    if(!is.null(blacklist)) {
      blacklist<-DBNbacktransform(blacklist,scorepar)
    }

    if(!is.null(startspace)) {
      startspace<-DBNbacktransform(startspace,scorepar)
    }

    if(!is.null(addspace)) {
      addspace<-DBNbacktransform(addspace,scorepar)
    }

    if(scorepar$split) { #we learn initial and transition structures separately
      if(scorepar$MDAG) {
        param1<-scorepar$paramsets[[scorepar$nsets]]
        param2<-scorepar$paramsets[[1]]
        param2$paramsets<-scorepar$paramsets[1:(scorepar$nsets-1)]
        param2$MDAG<-TRUE

      } else {
        param1<-scorepar$firstslice
        param2<-scorepar$otherslices
      }
      if(scoreout | !is.null(scoretable)) {
        cat("option scoreout always equals FALSE for DBNs with samestruct=FALSE, scoretable parameter is ignored \n")
      }


      cat("learning initial structure...\n")
      result.init<-iterativeMCMCplus1(param=param1,iterations,stepsave,plus1it=plus1it, MAP=MAP, posterior=posterior,alpha=alpha,cpdag=cpdag,
                                      moveprobs=moveprobs,softlimit=softlimit,hardlimit=hardlimit,
                                      startspace=startspace$init,blacklist=blacklist$init,gamma=gamma,
                                      verbose=verbose, chainout=chainout,scoreout=FALSE,mergecp=mergetype,
                                      addspace=addspace$init,scoretable=NULL,startorder=startorder$init,accum=accum,alphainit=alphainit,compress=compress)
      cat("learning transition structure...\n")
      result.trans<-iterativeMCMCplus1(param=param2,iterations,stepsave,plus1it=plus1it, MAP=MAP, posterior=posterior,alpha=alpha,cpdag=cpdag,
                                       moveprobs=moveprobs,softlimit=softlimit,hardlimit=hardlimit,
                                       startspace=startspace$trans,blacklist=blacklist$trans,gamma=gamma,
                                       verbose=verbose, chainout=chainout,scoreout=FALSE,mergecp=mergetype,
                                       addspace=addspace$trans,scoretable=NULL,startorder=startorder$trans,accum=accum, alphainit=alphainit,compress=compress)

      result<-mergeDBNres.it(result.init,result.trans,scorepar)

    } else {

      result<-iterativeMCMCplus1(param=scorepar,iterations,stepsave,plus1it=plus1it, MAP=MAP, posterior=posterior,alpha=alpha,cpdag=cpdag,
                                 moveprobs=moveprobs,softlimit=softlimit,hardlimit=hardlimit,
                                 startspace=startspace,blacklist=blacklist,gamma=gamma,
                                 verbose=verbose, chainout=chainout,scoreout=scoreout,mergecp=mergetype,
                                 addspace=addspace,scoretable=scoretable,startorder=startorder,accum=accum, alphainit=alphainit,compress=compress)
    }

  } else {
    result<-iterativeMCMCplus1(param=scorepar,iterations,stepsave,plus1it=plus1it, MAP=MAP, posterior=posterior,alpha=alpha,cpdag=cpdag,
                               moveprobs=moveprobs,softlimit=softlimit,hardlimit=hardlimit,
                               startspace=startspace,blacklist=blacklist,gamma=gamma,
                               verbose=verbose, chainout=chainout,scoreout=scoreout,mergecp=mergetype,
                               addspace=addspace,scoretable=scoretable,startorder=startorder,accum=accum,compress=compress)
  }
  result$info<-list()
  result$info$DBN<-scorepar$DBN
  if(scorepar$DBN) {
    result$info$nsmall<-scorepar$nsmall
    result$info$bgn<-scorepar$bgn
    result$info$split<-scorepar$split

  }
  result$info$algo<-"iterative order MCMC"
  if(is.null(startspace)) {
    result$info$spacealgo<-"PC"
  } else {
    result$info$spacealgo<-"user defined matrix"
  }
  result$info$iterations<-iterations
  result$info$plus1it<-length(result$max)
  result$info$samplesteps<-floor(iterations/stepsave)+1
  if(MAP) {
    result$info$sampletype<-"MAP"
  } else {
    result$info$sampletype<-"sample"
    result$info$threshold<-posterior
  }

  result$info$fncall<-match.call()
  attr(result,"class")<-"iterativeMCMC"

  return(result)

}

#'Calculating the BGe/BDe score of a single DAG
#'
#'This function calculates the score of a DAG defined by its adjacency matrix.
#'Acceptable data matrices are homogeneous with all variables of the same type:
#'continuous, binary or categorical.  The BGe score is evaluated in the case of
#'continuous data and the BDe score is evaluated for binary and categorical variables.
#'
#' @param scorepar an object of class \code{scoreparameters}, containing the data and
#'  scoring parameters; see constructor function \code{\link{scoreparameters}}
#' @param incidence a square matrix of dimensions equal to the number of nodes, representing the adjacency matrix of a DAG;  the matrix entries are in \code{\{0,1\}} such that \code{incidence[i,j]} equals 1 if there is a directed edge from node \code{i} to node \code{j} in the DAG and
#' \code{incidence[i,j]} equals 0 otherwise
#' @return the log of the BGe or BDe score of the DAG
#' @references Geiger D and Heckerman D (2002). Parameter priors for directed acyclic graphical models and the characterization of several probability distributions. The Annals of Statistics 30, 1412-1440.
#' @references Heckerman D and Geiger D (1995). Learning Bayesian networks: A unification for discrete and Gaussian domains. In Eleventh Conference on Uncertainty in Artificial Intelligence, pages 274-284.
#' @references Kuipers J, Moffa G and Heckerman D (2014). Addendum on the scoring of Gaussian directed acyclic graphical models. The Annals of Statistics 42, 1689-1691.
#' @examples
#' myScore<-scoreparameters("bde", Asia)
#' DAGscore(myScore, Asiamat)
#' @import pcalg
#' @export
#' @author Polina Suter, Jack Kuipers, the code partly derived from the order MCMC implementation from Kuipers J, Moffa G (2017) <doi:10.1080/01621459.2015.1133426>
DAGscore <- function(scorepar, incidence){
  if(scorepar$DBN) {
    stop("To calculate DBN score DBNscore should be used!")
  }
  n<-ncol(scorepar$data)
  if(scorepar$bgn==0) {
    mainnodes<-c(1:scorepar$n)
  } else {
    mainnodes<-c(1:n)[-scorepar$bgnodes]
  }
  P_local <- numeric(n)
  for (j in mainnodes)  { #j is a node at which scoring is done
    parentnodes <- which(incidence[,j]==1)
    P_local[j]<-DAGcorescore(j,parentnodes,scorepar$n,scorepar)
  }
  return(sum(P_local))
}


#'Calculating the BGe/BDe score of a single DBN
#'
#'This function calculates the score of a DBN defined by its compact adjacency matrix.
#'Acceptable data matrices are homogeneous with all variables of the same type: continuous,
#'binary or categorical.  The BGe score is evaluated in the case of continuous data and the BDe score is evaluated for binary and categorical variables.
#'
#' @param scorepar an object of class \code{scoreparameters}, containing the data and scoring parameters; see constructor function \code{\link{scoreparameters}}
#' @param incidence a square matrix, representing initial and transitional structure of a DBN; the size of matrix is 2*nsmall+bgn, where nsmall is the number of variables per time slice excluding static nodes and bgn is the number of static variables
#'  the matrix entries are in \code{\{0,1\}} such that \code{incidence[i,j]} equals
#'   1 if there is a directed edge from node \code{i} to node \code{j} in the DAG and
#' \code{incidence[i,j]} equals 0 otherwise
#' @return the log of the BGe or BDe score of the DBN
#' @examples
#' testscore<-scoreparameters("bge", DBNdata, DBN=TRUE, dbnpar=list(slices=5, b=3))
#' DBNscore(testscore, DBNmat)
#'
#' @export
#' @author Polina Suter, Jack Kuipers
DBNscore<-function(scorepar,incidence) {

  if(nrow(incidence)==ncol(incidence) & ncol(incidence)==(2*scorepar$nsmall+scorepar$bgn)) {

    incidence<-DBNbacktransform(incidence,scorepar)

    if(!scorepar$split) {
      P_local <- numeric(scorepar$nsmall)
      for (j in 1:scorepar$nsmall)  { #j is a node at which scoring is done
        parentnodes <- which(incidence[,j]==1)
        P_local[j]<-DAGcorescore(j,parentnodes,scorepar$n,scorepar)
      }

      return(sum(P_local))
    } else {
      P_local <- numeric(2*scorepar$nsmall)

      for (j in 1:scorepar$nsmall)  { #j is a node at which scoring is done
        parentnodes <- which(incidence$init[,j]==1)
        P_local[j]<-DAGcorescore(j,parentnodes,scorepar$n,scorepar$firstslice)
      }

      for (j in 1:scorepar$nsmall)  { #j is a node at which scoring is done
        parentnodes <- which(incidence$trans[,j]==1)
        P_local[j+scorepar$nsmall]<-DAGcorescore(j,parentnodes,scorepar$otherslices$n,scorepar$otherslices)
      }

      return(sum(P_local))

    }

  } else {
    stop("wrong dimensions of the adjacency matrix!")
  }
}
